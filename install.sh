# Copyright 2020 Google LLC..
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/bin/bash
# Zombies setup script.

set -e

VIRTUALENV_PATH=$HOME/"zombies-venv"

# Create virtual environment with python3
if [[ ! -d "${VIRTUALENV_PATH}" ]]; then
  virtualenv -p python3 "${VIRTUALENV_PATH}"
fi

# Activate virtual environment.
source ${VIRTUALENV_PATH}/bin/activate

# Install dependencies.
pip install -r "./src/bq_transfers/requirements.txt"

# Setup cloud environment.
PYTHONPATH=src/plugins:$PYTHONPATH
export PYTHONPATH

declare -a ACCOUNTS

find_config_value()
{

  
  NAME=$1

  FILE="./variables.tf"
  LINE_NO=$(grep -n "$NAME" "$FILE" | sed "s/:.*//")

  #echo "$LINE_NO"

  I=0
  LINE=""
  NOT_FOUND=1
  
  while [ "$NOT_FOUND" -eq 1 ]
  do
    read -r LINE
    I=$(( I + 1 ))
    if [[ ("$LINE" == *"default"*)  && ($I -gt $LINE_NO) ]]; then
      RESULT=$(echo "$LINE" | cut -d '=' -f2 | sed -e 's/^[[:space:]]*//' | sed -e 's/"//g')
      NOT_FOUND=0
    fi;
  
  done < "$FILE"

  echo "$RESULT"
}


find_accounts_values(){

  NAME=$1
  FILE="./variables.tf"
  
  LINE_NO=$(grep -n accounts_table "$FILE" | sed "s/:.*//")
  I=0
  J=0
  start=0
  LINE=""

  while read LINE; do
    I=$(( I + 1 ))
    
    if [[ ("$LINE" == *"default"* )  && ($I -gt $LINE_NO) ]]; then
      START=1
    fi;

    if [[ ($START -eq 1) && ("$LINE" == *"gads"* ) ]]; then
      JSON_LINE=$(echo "$LINE" |  grep -o "{.*}")
      MC=$(python3 -c "import sys, json; print(json.loads('$JSON_LINE')['mc'])")
      GADS=$(python3 -c "import sys, json; print(json.loads('$JSON_LINE')['gads'])")
      ACCOUNTS[$J]="$MC,$GADS"
      J=$(( J + 1 ))
    fi;
  done < "$FILE"

}

deploy_data_transfers(){

  GCP_PROJECT=$(find_config_value "variable \"gcp_project\"")
  MERCHANT_DATASET_NAME=$(find_config_value "variable \"merchant_dataset_name\"")
  GADS_DATASET_NAME=$(find_config_value "variable \"gads_dataset_name\"")
  ZOMBIES_DATA_LOCATION=$(find_config_value "variable \"zombies_data_location\"")
  SERVICE_ACCOUNT=$(find_config_value "variable \"zombies_sa\"")
  SERVICE_ACCOUNT="$SERVICE_ACCOUNT""@""$GCP_PROJECT"".iam.gserviceaccount.com"
  MERCHANT_SCHEDULE=$(find_config_value "variable \"merchant_schedule\"")
  GADS_SCHEDULE=$(find_config_value "variable \"gads_schedule\"")

  find_accounts_values "variable \"accounts_table\""
   
  echo "Checking Datasets status..."

  terraform import google_bigquery_dataset.merchant_dataset[0] "$MERCHANT_DATASET_NAME" || echo >&2 "Ignoring import failure"
  terraform import google_bigquery_dataset.gads_dataset[0] "$GADS_DATASET_NAME" || echo >&2 "Ignoring import failure"
  terraform apply -target=google_bigquery_dataset.merchant_dataset -target=google_bigquery_dataset.gads_dataset
  
  for I in ${ACCOUNTS[@]}
  do
    MC=$(echo "$I" | cut -d ',' -f1)
    GADS=$(echo "$I" | cut -d ',' -f2)
    
    echo "Creating transfer for Merchant $MC and GAds $GADS..."

    python ./src/bq_transfers/data_transfers.py \
      --requirements_file ./src/bq_transfers/requirements.txt \
      --project_id "$GCP_PROJECT" \
      --merchant_dataset_id "$MERCHANT_DATASET_NAME" \
      --gads_dataset_id "$GADS_DATASET_NAME" \
      --dataset_location "$ZOMBIES_DATA_LOCATION" \
      --gads_account_id "$GADS" \
      --merchant_account_id "$MC" \
      --service_account "$SERVICE_ACCOUNT" \
      --merchant_schedule "$MERCHANT_SCHEDULE" \
      --gads_schedule "$GADS_SCHEDULE"

  done;
}

CREATE_MERCHANT_AND_GADS_TRANSFERS=$(find_config_value "variable \"create_merchant_and_gads_transfers\"")

terraform init -upgrade

echo "$CREATE_MERCHANT_AND_GADS_TRANSFERS"

if [[ "$CREATE_MERCHANT_AND_GADS_TRANSFERS" == "true" ]]; then
  echo "Creating BQ Data Transfer for Merchant and GAds..."
  deploy_data_transfers
fi;

terraform apply --parallelism=1
