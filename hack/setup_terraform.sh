## Setup terraform envvars
# Usage:
#	. ./setup_terraform.sh

export TF_VAR_number_of_workers=3
export TF_VAR_do_token=$(cat ./secrets/DO_TOKEN)
export TF_VAR_wsrep_sst_user=$(cat ./secrets/WSREP_SST_USER)
export TF_VAR_wsrep_sst_pass=$(cat ./secrets/WSREP_SST_PASS)
export TF_VAR_mysql_user=$(cat ./secrets/MYSQL_USER)
export TF_VAR_mysql_pass=$(cat ./secrets/MYSQL_PASS)
export TF_VAR_mysql_root_pass=$(cat ./secrets/MYSQL_ROOT_PASS)
export TF_VAR_pub_key="~/.ssh/id_rsa.pub"
export TF_VAR_pvt_key="~/.ssh/id_rsa"
export TF_VAR_ssh_fingerprint=$(ssh-keygen -lf ~/.ssh/id_rsa.pub | awk '{print $2}')
