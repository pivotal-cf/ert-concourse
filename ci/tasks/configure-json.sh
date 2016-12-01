#!/bin/bash

set -e


# Set Vars
json_file_path="ert-concourse/json_templates/${pcf_iaas}/${terraform_template}"
json_file_template="${json_file_path}/ert-template.json"
json_file="json_file/ert.json"

cp ${json_file_template} ${json_file}

if [[ ! -f ${json_file} ]]; then
  echo "Error: cant find file=[${json_file}]"
  exit 1
fi


# Iaas Specific ERT  JSON Edits

if [[ -e ert-concourse/scripts/iaas-specific-config/${pcf_iaas}/run.sh ]]; then
  echo "Executing ${$pcf_iaas} IaaS specific config ..."
  ./ert-concourse/scripts/iaas-specific-config/${pcf_iaas}/run.sh
fi
