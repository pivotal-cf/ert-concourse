#!/bin/bash
set -e

#Make om-linux executable

sudo cp tool-om/om-linux /usr/local/bin
sudo chmod 755 /usr/local/bin/om-linux

mv /opt/terraform/terraform /usr/local/bin
CWD=$(pwd)
cd aws-prepare-get/terraform/c0-aws-base/
cp $CWD/pcfawsops-terraform-state-get/terraform.tfstate .

while read -r line
do
  `echo "$line" | awk '{print "export "$1"="$3}'`
done < <(terraform output)

export AWS_ACCESS_KEY_ID=`terraform state show aws_iam_access_key.pcf_iam_user_access_key | grep ^id | awk '{print $3}'`
export AWS_SECRET_ACCESS_KEY=`terraform state show aws_iam_access_key.pcf_iam_user_access_key | grep ^secret | awk '{print $3}'`
export RDS_PASSWORD=`terraform state show aws_db_instance.pcf_rds | grep ^password | awk '{print $3}'`

cd $CWD

# Set JSON Config Template and inster Concourse Parameter Values
output_file_path="json_file/"
json_file_path="ert-concourse/json-templates/${pcf_iaas}/${terraform_template}"
json_file_template="${json_file_path}/ert-template.json"
json_file="${json_file_path}/ert.json"

perl -pi -e "s/{{aws_zone_1}}/${az1}/g" ${json_file}
perl -pi -e "s/{{aws_zone_2}}/${az2}/g" ${json_file}
perl -pi -e "s/{{aws_zone_3}}/${az3}/g" ${json_file}
perl -pi -e "s/{{rds_host}}/${db_host}/g" ${json_file}
perl -pi -e "s/{{rds_user}}/${db_username}/g" ${json_file}
perl -pi -e "s/{{rds_password}}/${RDS_PASSWORD}/g" ${json_file}

perl -pi -e "s/{{aws_access_key}}/${AWS_ACCESS_KEY_ID}/g" ${json_file}
perl -pi -e "s%{{aws_secret_key}}%${AWS_SECRET_ACCESS_KEY}%g" ${json_file}
perl -pi -e "s/{{aws_region}}/${region}/g" ${json_file}
perl -pi -e "s/{{s3_endpoint}}/${S3_ESCAPED}/g" ${json_file}
perl -pi -e "s/{{syslog_host}}/${SYSLOG_HOST}/g" ${json_file}
mv ${json_file} ${output_file_path}
