#!/bin/bash
set -e

# Apply Changes in Opsman
echo "=============================================================================================="
echo "Applying OpsMan Changes to Deploy: ${guid_cf}"
echo "=============================================================================================="
om-linux --target https://opsman.$pcf_ert_domain -k \
       --username "$pcf_opsman_admin" \
       --password "$pcf_opsman_admin_passwd" \
  apply-changes
