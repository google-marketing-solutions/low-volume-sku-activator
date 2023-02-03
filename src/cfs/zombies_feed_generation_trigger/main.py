# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# -*- coding: utf-8 -*-

import os
import base64
import json
from google.api_core import datetime_helpers
from googleapiclient.discovery import build
from oauth2client.client import GoogleCredentials

credentials = GoogleCredentials.get_application_default()
service = build('dataflow', 'v1b3', credentials=credentials)

def trigger_job(event, context):
    """Background Cloud Function to be triggered by Cloud Storage.
       This generic function logs relevant data when a file is changed.
    Args:
        event (dict):  The dictionary with data specific to this type of event.
                       The `data` field contains a description of the event in
                       the Cloud Storage `object` format described here:
                       https://cloud.google.com/storage/docs/json_api/v1/objects#resource
        context (google.cloud.functions.Context): Metadata of triggering event.
    Returns:
        None; the output is written to Stackdriver Logging
    """

    GCP_PROJECT = os.environ.get('GCP_PROJECT')
    ZOMBIES_DATASET_NAME = os.environ.get('ZOMBIES_DATASET_NAME')
    DATAFLOW_BUCKET = os.environ.get('DATAFLOW_BUCKET')
    DATAFLOW_TEMPLATE_PATH = os.environ.get('DATAFLOW_TEMPLATE_PATH')
    DATAFLOW_TEMPLATE_NAME = os.environ.get('DATAFLOW_TEMPLATE_NAME')
    ACCOUNTS_CONFIG = json.loads(os.environ.get('ACCOUNTS_CONFIG'))
    DATAFLOW_SA = os.environ.get('DATAFLOW_SA')
    ZOMBIES_OPTIMISATION = os.environ.get('ZOMBIES_OPTIMISATION')
    
    data = base64.b64decode(event['data']).decode('utf-8')
    msg = json.loads(data)
    
    table_parts = msg['params']['destination_table_name_template'].split('_')
    gcs_path = f"gs://{DATAFLOW_BUCKET}/dataflow"
    gcs_template_path = f"{gcs_path}/{DATAFLOW_TEMPLATE_PATH}/{DATAFLOW_TEMPLATE_NAME}"

    run_date = _get_date(msg)

    zombies_bucket = _get_zombies_bucket(table_parts[1], table_parts[2],
                                         ACCOUNTS_CONFIG)

    body = {
        "jobName": "zb-" + "-".join(table_parts[1:3]),
        "parameters": {
            "gcs_destination": f"{zombies_bucket}/zombies_feed_{table_parts[1]}_{table_parts[2]}",
            "bq_gcs_location": f"{gcs_path}/staging",        
            "query": f"""SELECT offer_id, item_group_id, "zombie" as custom_label_100
                         FROM `{GCP_PROJECT}.{ZOMBIES_DATASET_NAME}.ZombieProducts_{table_parts[1]}_{table_parts[2]}_*` 
                         WHERE
                          _TABLE_SUFFIX = {run_date}
                          AND avg_{ZOMBIES_OPTIMISATION} < {ZOMBIES_OPTIMISATION}_threshold"""
         },
        "environment": {
            "tempLocation": f"{gcs_path}/temp",
            "serviceAccountEmail": DATAFLOW_SA
         },
    }
    
    request = service.projects()\
        .templates()\
        .launch(projectId=GCP_PROJECT, gcsPath=gcs_template_path, body=body)\
        .execute()

def _get_zombies_bucket(merchant_acc, gads_acc, accounts_config):
  """Extracts the right url for the merchant and gads account pair.

  Args:
    merchant_acc: string representing the merchant account id
    gads_acc: string representing the gads account id
    accounts_config: javascript object with the configuration per each
    merchant_acc & gads_acc pairs

  Returns:
    A string representing gcs url
  """
  for index, line in accounts_config.items():
    print(index, line)
    if line["mc"] == merchant_acc and line["gads"] == gads_acc:
        return line["gcs_url"]

  raise Exception("No account match found in config")

def _get_date(msg):
  """Extracts the date from the message.

  Args:
    msg: A JSON object representing the message

  Returns:
    A string representing the date of the data to be processed in YYYYMMDD
    format
  """

  runtime = msg['runTime']
  date = datetime_helpers.from_rfc3339(runtime)
  return date.strftime('%Y%m%d')