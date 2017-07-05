#!/bin/bash
set -e

json_file="json_file/ert.json"

# Setup OM Tool
sudo cp tool-om/om-linux /usr/local/bin
sudo chmod 755 /usr/local/bin/om-linux

# Set Vars

# Test if the ssl cert var from concourse is set to 'generate'.  If so, script will gen a self signed, otherwise will assume its a provided cert
if [[ ${pcf_ert_ssl_cert} == "generate" ]]; then
  echo "=============================================================================================="
  echo "Generating Self Signed Certs for sys.${pcf_ert_domain} & cfapps.${pcf_ert_domain} ..."
  echo "=============================================================================================="
  ert-concourse/scripts/ssl/gen_ssl_certs.sh "sys.${pcf_ert_domain}" "cfapps.${pcf_ert_domain}"
  export pcf_ert_ssl_cert=$(cat sys.${pcf_ert_domain}.crt)
  export pcf_ert_ssl_key=$(cat sys.${pcf_ert_domain}.key)
fi

# Test if the saml cert var from concourse is set to 'generate'.  If so, script will gen a self signed, otherwise will assume its a provided cert
if [[ ${pcf_ert_saml_cert} == "generate" ]]; then
  echo "=============================================================================================="
  echo "Generating Self Signed Certs for login.sys.${pcf_ert_domain} ..."
  echo "=============================================================================================="
  ert-concourse/scripts/ssl/gen_ssl_certs.sh "login.sys.${pcf_ert_domain}"
  export pcf_ert_saml_cert=$(cat login.sys.${pcf_ert_domain}.crt)
  export pcf_ert_saml_key=$(cat login.sys.${pcf_ert_domain}.key)
fi

my_pcf_ert_ssl_cert=$(echo ${pcf_ert_ssl_cert} | sed 's/\s\+/\\\\r\\\\n/g' | sed 's/\\\\r\\\\nCERTIFICATE/ CERTIFICATE/g')
my_pcf_ert_ssl_key=$(echo ${pcf_ert_ssl_key} | sed 's/\s\+/\\\\r\\\\n/g' | sed 's/\\\\r\\\\nRSA\\\\r\\\\nPRIVATE\\\\r\\\\nKEY/ RSA PRIVATE KEY/g')
my_pcf_ert_saml_cert=$(echo ${pcf_ert_saml_cert} | sed 's/\s\+/\\\\r\\\\n/g' | sed 's/\\\\r\\\\nCERTIFICATE/ CERTIFICATE/g')
my_pcf_ert_saml_key=$(echo ${pcf_ert_saml_key} | sed 's/\s\+/\\\\r\\\\n/g' | sed 's/\\\\r\\\\nRSA\\\\r\\\\nPRIVATE\\\\r\\\\nKEY/ RSA PRIVATE KEY/g')
perl -pi -e "s|{{pcf_ert_networking_pointofentry}}|${pcf_ert_networking_pointofentry}|g" ${json_file}

my_web_lb="${terraform_prefix}-web-lb"
if [[ ${pcf_ert_networking_pointofentry} == "haproxy" ]]; then
  perl -pi -e "s|{{pcf-web-lb-haproxy}}|${my_web_lb}|g" ${json_file}
  perl -pi -e "s|{{pcf-web-lb-router}}||g" ${json_file}
fi
if [[ ${pcf_ert_networking_pointofentry} == "external_ssl" || ${pcf_ert_networking_pointofentry} == "external_non_ssl" ]]; then
  perl -pi -e "s|{{pcf-web-lb-router}}|${my_web_lb}|g" ${json_file}
  perl -pi -e "s|{{pcf-web-lb-haproxy}}||g" ${json_file}
fi

perl -pi -e "s|{{pcf_ert_ssl_cert}}|${my_pcf_ert_ssl_cert}|g" ${json_file}
perl -pi -e "s|{{pcf_ert_ssl_key}}|${my_pcf_ert_ssl_key}|g" ${json_file}
perl -pi -e "s|{{pcf_ert_saml_cert}}|${my_pcf_ert_saml_cert}|g" ${json_file}
perl -pi -e "s|{{pcf_ert_saml_key}}|${my_pcf_ert_saml_key}|g" ${json_file}
perl -pi -e "s/{{pcf_ert_domain}}/${pcf_ert_domain}/g" ${json_file}
perl -pi -e "s/{{pcf_az_1}}/${pcf_az_1}/g" ${json_file}
perl -pi -e "s/{{pcf_az_2}}/${pcf_az_2}/g" ${json_file}
perl -pi -e "s/{{pcf_az_3}}/${pcf_az_3}/g" ${json_file}
perl -pi -e "s/{{terraform_prefix}}/${terraform_prefix}/g" ${json_file}


if [[ "${azure_access_key}" != "" ]]; then
cat ${json_file} | jq \
  --arg azure_access_key "${azure_access_key}" \
  --arg azure_account_name "${azure_account_name}" \
  --arg azure_buildpacks_container "${azure_buildpacks_container}" \
  --arg azure_droplets_container "${azure_droplets_container}" \
  --arg azure_packages_container "${azure_packages_container}" \
  --arg azure_resources_container "${azure_resources_container}" \
    '
    .properties.properties |= .+ {
    ".properties.system_blobstore.external_azure.access_key": {
            "value": {
                "secret": $azure_access_key
            }
        },
        ".properties.system_blobstore": {
            "value": "external_azure"
        },
        ".properties.system_blobstore.external_azure.account_name": {
            "value": $azure_account_name
        },
        ".properties.system_blobstore.external_azure.buildpacks_container": {
            "value": $azure_buildpacks_container
        },
        ".properties.system_blobstore.external_azure.droplets_container": {
            "value": $azure_droplets_container
        },
        ".properties.system_blobstore.external_azure.packages_container": {
            "value": $azure_packages_container
        },
        ".properties.system_blobstore.external_azure.resources_container": {
            "value": $azure_resources_container
        }
        }
    ' > /tmp/ert.json
    mv /tmp/ert.json ${json_file}
fi

echo "file=[${json_file}]"
echo $file | cat $file
echo "Flushed the json file to output"

if [[ ! -f ${json_file} ]]; then
  echo "Error: cant find file=[${json_file}]"
  exit 1
fi

function fn_om_linux_curl_fail {
    echo ERROR
    echo stdout:\n
    cat /tmp/rqst_stdout.log >&2
    echo
    echo stderr:\n
    cat /tmp/rqst_stderr.log >&2
}

function fn_om_linux_curl {
  local curl_method=$1
  local curl_path=$2
  local curl_data=$3

  args="--target https://opsman.$pcf_ert_domain -k \
    --username $pcf_opsman_admin \
    --password $pcf_opsman_admin_passwd  \
    curl \
    --request $curl_method \
    --path $curl_path"

  rm -f /tmp/rqst_stdout.log /tmp/rqst_stderr.log

  set +e
  if [ -n "$curl_data" ]; then
    om-linux ${args} --data "${curl_data// /\\ }" 1> /tmp/rqst_stdout.log 2> /tmp/rqst_stderr.log
  else
    om-linux ${args} 1> /tmp/rqst_stdout.log 2> /tmp/rqst_stderr.log
  fi

  if [ $? -ne 0 ]; then
    fn_om_linux_curl_fail
    exit 1
  fi

  grep -s -q "Status: 200 OK" /tmp/rqst_stderr.log
  if [ $? -ne 0 ]; then
    fn_om_linux_curl_fail
    exit 1
  fi

  set -e
  cat /tmp/rqst_stdout.log
}

echo "=============================================================================================="
echo "Deploying ERT @ https://opsman.$pcf_ert_domain ..."
echo "=============================================================================================="
# Get cf Product Guid
guid_cf=$(fn_om_linux_curl "GET" "/api/v0/staged/products" \
            | jq '.[] | select(.type == "cf") | .guid' | tr -d '"' | grep "cf-.*")

echo "=============================================================================================="
echo "Found ERT Deployment with guid of ${guid_cf}"
echo "=============================================================================================="

# Set Networks & AZs
echo "=============================================================================================="
echo "Setting Availability Zones & Networks for: ${guid_cf}"
echo "=============================================================================================="

json_net_and_az=$(cat ${json_file} | jq -c .networks_and_azs)
fn_om_linux_curl "PUT" "/api/v0/staged/products/${guid_cf}/networks_and_azs" "$json_net_and_az"

# Set ERT Properties
echo "=============================================================================================="
echo "Setting Properties for: ${guid_cf}"
echo "=============================================================================================="

json_properties=$(cat ${json_file} | jq -c .properties)
fn_om_linux_curl "PUT" "/api/v0/staged/products/${guid_cf}/properties" "$json_properties"

# Set Resource Configs
echo "=============================================================================================="
echo "Setting Resource Job Properties for: ${guid_cf}"
echo "=============================================================================================="
json_jobs_configs=$(cat ${json_file} | jq .jobs )
json_job_guids=$(fn_om_linux_curl "GET" "/api/v0/staged/products/${guid_cf}/jobs" | jq .)
opsman_avail_jobs=$(echo ${json_job_guids} | jq .jobs[].name | tr -d '"')

#for job in $(echo ${json_jobs_configs} | jq . | jq 'keys' | jq .[] | tr -d '"'); do
for job in ${opsman_avail_jobs}; do

 json_job_guid_cmd="echo \${json_job_guids} | jq '.jobs[] | select(.name == \"${job}\") | .guid' | tr -d '\"'"
 json_job_guid=$(eval ${json_job_guid_cmd})
 json_job_config_cmd="echo \${json_jobs_configs} | jq -c '.[\"${job}\"]' "
 json_job_config=$(eval ${json_job_config_cmd})
 echo "---------------------------------------------------------------------------------------------"
 echo "Setting ${json_job_guid} with --data=${json_job_config}..."
 fn_om_linux_curl "PUT" "/api/v0/staged/products/${guid_cf}/jobs/${json_job_guid}/resource_config" "${json_job_config}"

done
