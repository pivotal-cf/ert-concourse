#!/bin/bash
set -e

# Get JSON for ERT
json_file="json_file/ert.json"

#######################################
############## Functions ##############
#######################################

function fn_opsman_auth {
    ### No Inputs,   reads from vars set by config-director-json and authenticates to OpsMan

    if [[ -f mycookiejar ]]; then
      rm -rf mycookiejar
    fi
    # GET JSESSIONID
    url_authorize=$(fn_opsman_curl "GET" "auth/cloudfoundry"| grep "Redirecting to" | awk '{print$3}' | sed 's/.\{3\}$//' | sed 's/http.*:443\///')
    chk_session_id=$(fn_opsman_curl "GET" $url_authorize| grep "JSESSIONID" | awk '{print$2}' | awk -F"=" '{print$2}' | tr -d ';')
    cookie_session_id=$(cat mycookiejar | grep "JSESSIONID" | awk '{print$7}')

    # Validate
    if [[ ${chk_session_id} != ${cookie_session_id} || -z ${cookie_session_id} ]]; then
      fn_err "fn_opsman_auth has failed to get a JSESSIONID!!!"
    else
      echo "PASS: fn_opsman_auth get JSESSIONID has succeeded..."
    fi

    # POST Opsman Creds to get redirect for token
    xuaacsrf=$(cat mycookiejar | grep X-Uaa-Csrf | awk '{print$7}')
    rqst_form_data="-d 'username=${pcf_opsman_admin}&password=${pcf_opsman_admin_passwd}&X-Uaa-Csrf=${xuaacsrf}'"
    chk_login=$(fn_opsman_curl "POST" "uaa/login.do" "${xuaacsrf}" "--NOENCODE" "${rqst_form_data}" | grep "Location:" | awk '{print$2}' | awk -F '&' '{print$4}')
    url_authorize_state=$(echo "https://${opsman_host}/${url_authorize}" | awk -F '&' '{print$4}')

    # Validate
    if [[ ! ${chk_login} == ${url_authorize_state} || -z ${chk_login} ]]; then
      echo "chk=$chk_login"
      echo "val=$url_authorize_state"
      fn_err "fn_opsman_auth has failed to login with opsman creds!!!"
    else
      echo "chk=$chk_login"
      echo "val=$url_authorize_state"
      echo "PASS: fn_opsman_auth login with opsman creds succeeded..."
    fi

    # GET uaa token(s)
    url_token=$(fn_opsman_curl "GET" $url_authorize | grep "Location" | awk '{print$2}' | tr -d '\n')
    url_token_code=$(echo $url_token | awk -F "?" '{print$2}' | awk -F '&' '{print$1}' | awk -F '=' '{print$2}' )
    url_token_state=$(echo $url_token | awk -F "?" '{print$2}' | awk -F '&' '{print$2}' | awk -F '=' '{print$2}' )
    url_token=$(echo "auth/cloudfoundry/callback?code=${url_token_code}&state=${url_token_state}")
    chk_uaa_access_token=$(fn_opsman_curl "GET" $url_token "--NOENCODE" | grep "uaa_access_token" | awk '{print$2}' | awk -F ';' '{print$1}' | sed 's/uaa_access_token=//')
    cookie_uaa_access_token=$(cat mycookiejar | grep "uaa_access_token" | awk '{print$7}')

    # Validate
    if [[ ${chk_uaa_access_token} != ${cookie_uaa_access_token} || -z ${chk_uaa_access_token} ]]; then
      echo "chk_uaa_access_token=${chk_uaa_access_token}"
      echo "cookie_uaa_access_token=${cookie_uaa_access_token}"
      fn_err "fn_opsman_auth has failed to get proper uaa tokens!!!"
    else
      #echo "chk_uaa_access_token=${chk_uaa_access_token}"
      #echo "cookie_uaa_access_token=${cookie_uaa_access_token}"
      echo "PASS: fn_opsman_auth get proper uaa tokens succeeded..."
    fi
}

function fn_opsman_curl() {
  ####### Curl Core Command Flags #######

              curl_cmd="curl -k -s -i ${6} --cookie mycookiejar --cookie-jar mycookiejar -X $1 "

  ####### Headers #######

              curl_headers="-H \"Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8\""
              curl_headers="${curl_headers} -H \"Accept-Encoding: gzip, deflate, br\""
              curl_headers="${curl_headers} -H \"Accept-Language: en-US,en;q=0.8\""
              curl_headers="${curl_headers} -H \"Cache-Control: max-age=0\""
              curl_headers="${curl_headers} -H \"Connection: keep-alive\""
              curl_headers="${curl_headers} -H \"Host: ${opsman_host}\""
              curl_headers="${curl_headers} -H \"Upgrade-Insecure-Requests: 1\""


            if [[ $4 != "--NOENCODE" ]]; then
              curl_headers="${curl_headers} -H \"Content-Type: application/x-www-form-urlencoded\""
            fi

            if [[ ($2 == "uaa/login.do" && $1 == "POST") ]]; then
              curl_headers="${curl_headers} -H \"Cookie: X-Uaa-Csrf=$3\""
            fi

  ####### Host URL Builder #######

            curl_host="https://${opsman_host}/${2}"

  ####### Post Form Data Builder #######

            if [[ ! -z ${3} && ${1} == "POST" && ${4} != "--NOENCODE" && ! -z ${5} ]]; then
                  if [[ ${2} == *"az_and_network_assignments"* ]]; then
                    curl_form_data="-d \"utf8=%E2%9C%93&_method=patch&authenticity_token=${3}${5}\""
                  else
                    curl_form_data="-d \"utf8=%E2%9C%93&_method=put&authenticity_token=${3}${5}\""
                  fi
                  echo "Im Gonna use this for data: ${curl_form_data}"
            elif [[ ${1} == "POST" && ! -z ${5} ]]; then
                  curl_form_data="${5}"
            else
                  echo "NO POST DATA ..."
            fi

  ####### Curl Command Exec Builder #######

            if [[ ${1} == "POST" ]]; then
              cmd=$(echo "${curl_cmd} ${curl_headers} ${curl_form_data} '${curl_host}'" | tr -d '\n' | tr -d '\r')
            else
              cmd=$(echo "${curl_cmd} ${curl_headers} '${curl_host}'" | tr -d '\n' | tr -d '\r')
            fi
            echo "DEBUG_CMD=${cmd}"
            echo "DEBUG_CMD_LEN=${#cmd}"
            fn_run $cmd
}

function fn_json_to_post_data {

   return_var=""

   if [[ $2 == "var" ]]; then
     fn_metadata_keys_cmd="echo \$${1}_json | jq 'keys' | jq .[]"
     fn_metadata_cmd="echo \$${1}_json"
   elif [[ $2 == "file" ]]; then
     fn_metadata_keys_cmd="cat ${json_file_path}/${3}.json | jq .[].${1} | jq 'keys' | jq .[]"
     fn_metadata_cmd="cat ${json_file_path}/${3}.json | jq .[].${1}"
   else
     fn_err "$2 is not a matching json source type!!!"
   fi

   if [[ $(eval $fn_metadata_keys_cmd | grep '"pipeline_extension"' | wc -l) -eq 0 ]]; then

         for key in $(eval $fn_metadata_keys_cmd); do
           if [[ $(echo $key | tr -d '"') != "pipeline_extension" ]]; then
             fn_metadata_key_value=$(eval $fn_metadata_cmd | jq .${key})
             key=$(echo $key | tr -d '"')
             fn_metadata_key_value=$(echo $fn_metadata_key_value | sed 's/^"//' | sed 's/"$//')
             return_var="${return_var}&$key=$fn_metadata_key_value"
          else
             echo ""
          fi
         done

   else
          ext_json_data=$(eval $fn_metadata_cmd | jq .)
          ext_cmd="$(eval $fn_metadata_cmd |  jq .pipeline_extension | tr -d '"') \${ext_json_data}"
          return_var=$(eval ${ext_cmd})
   fi

   echo ${return_var}
}

function fn_urlencode {
   local unencoded=${@}
   encoded=$(echo $unencoded | perl -pe 's/([^-_.~A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg')
   #opsman "=,&,\crlf"" fixes, calls fail with these strings encoded
   encoded=$(echo ${encoded} | sed s'/%3D/=/g')
   encoded=$(echo ${encoded} | sed s'/%26/\&/g')
   encoded=$(echo ${encoded} | sed s'/%0A//g')

   echo ${encoded} | tr -d '\n' | tr -d '\r'
}

function fn_err {
   echo "config-director-json_err: ${1:-"Unknown Error"}"
   exit 1
}

function fn_run {
   printf "%s " ${@}
   eval "${@}"
   printf " # [%3d]\n" ${?}
}

#######################################
############# Main Logic ##############
#######################################


# Auth to Opsman
fn_opsman_auth
csrf_token=$(fn_opsman_curl "GET" "" | grep csrf-token | awk '{print$3}' | sed 's/content=\"//' | sed 's/\"$//')

# Verify we have a current csrf-token
if [[ -z ${csrf_token} ]]; then
  fn_err "fn_config_director has failed to get csrf_token!!!"
else
  echo "csrf_token=${csrf_token}"
  ## CSRF Tokens with '=' need to be re-urlencoded back to %3D
  csrf_encoded_token=$(fn_urlencode ${csrf_token} | sed 's|\=|%3D|g')
  echo "csrf_encoded_token=${csrf_encoded_token}"
fi
