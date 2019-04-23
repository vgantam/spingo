#!/bin/bash

# PREREQUISITES
# logged-in to gcloud: `gcloud auth login --project np-platforms-cd-thd`
# logged into vault
# `export VAULT_ADDR=https://vault.ioq1.homedepot.com:10231`
# `vault login <some token>`

# if you need to delete the service account, see 00-delete-terraform-account.sh

####################################################
########             Dependencies           ######## 
####################################################

# ensure that the required commands are present needed to run this script
commands="vault gcloud openssl"
for i in $commands
do
  if ! [ -x "$(command -v "$i")" ]; then
    echo "Error: $i is not installed." >&2
    exit 1
  fi
done

echo "enabling compute.googleapis.com service"
gcloud services enable compute.googleapis.com
echo "enabling iam.googleapis.com service"
gcloud services enable iam.googleapis.com
echo "enabling sqladmin.googleapis.com service"
gcloud services enable sqladmin.googleapis.com

echo "-----------------------------------------------------------------------------"
CURR_PROJ=$(gcloud config list --format 'value(core.project)' 2>/dev/null)
echo "Current gcloud project is : $CURR_PROJ"
echo "-----------------------------------------------------------------------------"
PS3="Enter the number for the Google Cloud Project to setup Spinnaker on (ctrl-c to exit) : ";
select projs in $(gcloud config list --format 'value(core.project)' 2>/dev/null)
do
    if [ "$projs" == "" ]; then
        echo "You must select a Google Cloud Project"
    else
        echo "-----------------------------------------------------------------------------"
        echo "Google Cloud Project $projs selected"
        PROJECT="$projs"
        break;
    fi
done
DOMAIN="$(gcloud config list account --format 'value(core.account)' 2>/dev/null | cut -d'@' -f2)"
TERRAFORM_REMOTE_GCS_NAME="$PROJECT-tf"
TERRAFORM_REMOTE_GCS_LOCATION="us-east1"
TERRAFORM_REMOTE_GCS_STORAGE_CLASS="regional"
SERVICE_ACCOUNT_NAME="terraform-account"
SERVICE_ACCOUNT_DEST="terraform-account.json"
ONBOARDING_BUCKET="$PROJECT-spinnaker-onboarding"

echo "creating $SERVICE_ACCOUNT_NAME service account"
gcloud iam service-accounts create \
    "$SERVICE_ACCOUNT_NAME" \
    --display-name "$SERVICE_ACCOUNT_NAME"

SA_EMAIL=$(gcloud iam service-accounts list \
    --filter="displayName:${SERVICE_ACCOUNT_NAME}" \
    --format='value(email)')

PROJECT=$(gcloud info --format='value(config.project)')

echo "adding roles to $SERVICE_ACCOUNT_NAME"
gcloud --no-user-output-enabled projects add-iam-policy-binding "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role='roles/resourcemanager.projectIamAdmin'
gcloud --no-user-output-enabled projects add-iam-policy-binding "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role='roles/iam.serviceAccountAdmin'
gcloud --no-user-output-enabled projects add-iam-policy-binding "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role 'roles/iam.serviceAccountKeyAdmin'
gcloud --no-user-output-enabled projects add-iam-policy-binding "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role='roles/compute.admin'
gcloud --no-user-output-enabled projects add-iam-policy-binding "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role='roles/container.admin'
gcloud --no-user-output-enabled projects add-iam-policy-binding "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role='roles/storage.admin'
gcloud --no-user-output-enabled projects add-iam-policy-binding "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role='roles/iam.serviceAccountUser'
gcloud --no-user-output-enabled projects add-iam-policy-binding "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role='roles/dns.admin'
gcloud --no-user-output-enabled projects add-iam-policy-binding "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role='roles/redis.admin'
gcloud --no-user-output-enabled projects add-iam-policy-binding  "$PROJECT" \
    --member serviceAccount:"$SA_EMAIL" \
    --role='roles/cloudsql.admin'

echo "generating keys for $SERVICE_ACCOUNT_NAME"
gcloud iam service-accounts keys create "$SERVICE_ACCOUNT_DEST" \
    --iam-account "$SA_EMAIL"

echo "writing $SERVICE_ACCOUNT_DEST to vault in secret/$PROJECT/$SERVICE_ACCOUNT_NAME"
vault write secret/"$PROJECT"/"$SERVICE_ACCOUNT_NAME" "$PROJECT"=@${SERVICE_ACCOUNT_DEST}

echo "create the bucket that will store the Terraform State"
gsutil mb -p "$PROJECT" -c "$TERRAFORM_REMOTE_GCS_STORAGE_CLASS" -l "$TERRAFORM_REMOTE_GCS_LOCATION" gs://"$TERRAFORM_REMOTE_GCS_NAME"/

echo "create the bucket that will store the onboarding information from teams"
gsutil mb -p "$PROJECT" gs://"$ONBOARDING_BUCKET"/

echo "set permissions of onboarding bucket to be creator for domain of $DOMAIN"
gsutil iam ch "domain:$DOMAIN:objectCreator" gs://"$ONBOARDING_BUCKET"

vault read -field "value"  secret/"$PROJECT"/keystore_pass

KEYSTORE_EXISTS=$(echo "$?")

if [ ! "$KEYSTORE_EXISTS" == "0" ]; then
    echo "There is no keystore password stored within vault. Please enter a password you want to use or leave blank to create a random one."
    read USER_KEY_PASS
    if [ "$USER_KEY_PASS" == "" ]; then
        KEY_PASS=$(openssl rand -base64 32)
    else
        KEY_PASS="$USER_KEY_PASS"
    fi
    vault write secret/"$PROJECT"/keystore_pass "value=$KEY_PASS"
fi
