#!/bin/bash

set -e


# Set Vars
json_file_path="azure-concourse/json-opsman/${azure_pcf_terraform_template}"
json_file_template="${json_file_path}/ert-template.json"
json_file="json_file/ert.json"

cp ${json_file_template} ${json_file}

if [[ ! -f ${json_file} ]]; then
  echo "Error: cant find file=[${json_file}]"
  exit 1
fi


##############################################################################
# Azure Specific                                                             #
##############################################################################
