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
from google.cloud import bigquery

def trigger_job(event, context):
    """Cloud Function to be triggered by PubSub after BigQuery Scheduled Query completion.
       This function generates the low volume sku suplemental feed using SQL.
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
    ACCOUNTS_CONFIG = json.loads(os.environ.get('ACCOUNTS_CONFIG'))
    ZOMBIES_SQL_CONDITION = os.environ.get('ZOMBIES_SQL_CONDITION')
    ZOMBIES_FEED_LABEL_INDEX = os.environ.get('ZOMBIES_FEED_LABEL_INDEX')

    data = base64.b64decode(event['data']).decode('utf-8')
    msg = json.loads(data)

    accounts_id = msg['params']['destination_table_name_template'].split('_')
    mc_id = accounts_id[1]
    gads_id = accounts_id[2]
    run_date = _get_date(msg)

    zombies_bucket = _get_zombies_bucket(mc_id, gads_id,
                                         ACCOUNTS_CONFIG)
    gcs_destination = f'{zombies_bucket}/low_volume_skus_{mc_id}_{gads_id}_*.txt'

    query = f"""
      EXPORT DATA OPTIONS(
        uri='{gcs_destination}',
        format='CSV',
        overwrite=true,
        header=true,
        field_delimiter='\t')
      AS
        SELECT DISTINCT * FROM (
          SELECT offer_id, item_group_id, country, 'low_volume_sku' as custom_label_{ZOMBIES_FEED_LABEL_INDEX}
          FROM `{GCP_PROJECT}.{ZOMBIES_DATASET_NAME}.LowVolumeSkus_{mc_id}_{gads_id}_{run_date}`
          WHERE        
            {ZOMBIES_SQL_CONDITION}
        )
    """

    job_config = bigquery.job.QueryJobConfig()

    bigquery.Client(project=GCP_PROJECT).query(query, job_config=job_config);

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