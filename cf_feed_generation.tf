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
# Generates an archive of the source code compressed as a .zip file.

data "archive_file" "source" {
    count = var.generate_feed_files ? 1 : 0
    type        = "zip"
    source_dir  = "src/cfs/low_volume_skus_feed_generation"
    output_path = "/tmp/low_volume_skus_feed_generation.zip"
    depends_on   = []
}

# Add source code zip to the Cloud Function's bucket
resource "google_storage_bucket_object" "zip" {
    count = var.generate_feed_files ? 1 : 0
    source       = data.archive_file.source[0].output_path
    content_type = "application/zip"

    # Append to the MD5 checksum of the files's content
    # to force the zip to be updated as soon as a change occurs
    name         = "src-${data.archive_file.source[0].output_md5}.zip"
    bucket       = google_storage_bucket.zombies_bucket.name

    # Dependencies are automatically inferred so these lines can be deleted
    depends_on   = [
        google_storage_bucket.zombies_bucket,    
    ]
}

# Create the Cloud function triggered by a `Finalize` event on the bucket
resource "google_cloudfunctions_function" "function" {
    count = var.generate_feed_files ? 1 : 0
    depends_on            = [      
        google_storage_bucket_object.zip[0],
        google_service_account.service_account,
        google_project_service.enable_cloudfunctions,
        google_project_service.enable_cloudbuild,
        google_storage_bucket.zombies_bucket       
    ]
    name                  = "low_volume_skus_feed_generation"
    runtime               = "python38"

    environment_variables = {
        GCP_PROJECT = var.gcp_project,
        ACCOUNTS_CONFIG = jsonencode(var.accounts_table),
        ZOMBIES_DATASET_NAME = var.zombies_dataset_name,
        ZOMBIES_SQL_CONDITION = var.zombies_sql_condition,
        ZOMBIES_FEED_LABEL_INDEX = var.zombies_feed_label_index,
    }

    # Get the source code of the cloud function as a Zip compression
    source_archive_bucket = google_storage_bucket.zombies_bucket.name
    source_archive_object = google_storage_bucket_object.zip[0].name

    # Must match the function name in the cloud function `main.py` source code
    entry_point           = "trigger_job"
    
    # 
    event_trigger {
      event_type = "google.pubsub.topic.publish"
      resource = google_pubsub_topic.zombies_bq_sq_completed_topic.id
    }
}