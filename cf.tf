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
    source_dir  = "src/cfs/zombies_feed_generation_trigger"
    output_path = "/tmp/zombies_feed_generation_trigger.zip"
    depends_on   = [
        ]
}

resource "google_storage_bucket" "zombies_bucket" {
  count = var.generate_feed_files ? 1 : 0
  project = data.google_project.project.project_id
  name          = var.zombies_bucket_name
  location      = var.zombies_bucket_location
  force_destroy = true
  uniform_bucket_level_access = true
  depends_on    = [google_service_account.service_account,
                  ]  
}

# Add source code zip to the Cloud Function's bucket
resource "google_storage_bucket_object" "zip" {
    count = var.generate_feed_files ? 1 : 0
    source       = data.archive_file.source[0].output_path
    content_type = "application/zip"

    # Append to the MD5 checksum of the files's content
    # to force the zip to be updated as soon as a change occurs
    name         = "src-${data.archive_file.source[0].output_md5}.zip"
    bucket       = google_storage_bucket.zombies_bucket[0].name

    # Dependencies are automatically inferred so these lines can be deleted
    depends_on   = [
        google_storage_bucket.zombies_bucket,  # declared in `storage.tf`      
    ]
}

# Create the Cloud function triggered by a `Finalize` event on the bucket
resource "google_cloudfunctions_function" "function" {
    count = var.generate_feed_files ? 1 : 0
    depends_on            = [      
        google_storage_bucket_object.zip,
        google_project_service.enable_cloudbuild,
        google_storage_bucket.zombies_bucket,
        null_resource.deploy_dataflow_template
    ]
    name                  = "zombies_feed_generation_trigger"
    runtime               = "python38"

    environment_variables = {
        GCP_PROJECT = var.gcp_project,
        ACCOUNTS_CONFIG = jsonencode(var.accounts_table),
        ZOMBIES_DATASET_NAME = var.zombies_dataset_name,
        DATAFLOW_REGION = var.gcp_region,
        DATAFLOW_BUCKET = var.zombies_bucket_name,
        DATAFLOW_TEMPLATE_PATH = "templates",
        DATAFLOW_TEMPLATE_NAME = "zombies_on_steroids_df_pipeline",
        DATAFLOW_SA = var.zombies_sa,
        ZOMBIES_OPTIMISATION = var.zombies_optimisation,
    }

    # Get the source code of the cloud function as a Zip compression
    source_archive_bucket = google_storage_bucket.zombies_bucket[0].name
    source_archive_object = google_storage_bucket_object.zip[0].name

    # Must match the function name in the cloud function `main.py` source code
    entry_point           = "trigger_job"
    
    # 
    event_trigger {
      event_type = "google.pubsub.topic.publish"
      resource = google_pubsub_topic.zombies_bq_sq_completed_topic.id
    }
}