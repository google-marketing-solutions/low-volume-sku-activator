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

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

data "google_project" "project" {
}


resource "google_service_account" "service_account" {
  account_id   = var.zombies_sa
  display_name = "Zombies Service Account"
}

resource "null_resource" "generate_feed_files" {

  count = var.generate_feed_files ? 1 : 0

}

resource "google_project_service" "enable_cloudbuild" {
  project = var.gcp_project
  service = "cloudbuild.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}

resource "google_project_service" "enable_bqdt" {
  project = var.gcp_project
  service = "bigquerydatatransfer.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}

resource "google_project_service" "enable_pubsub" {
  project = var.gcp_project
  service = "pubsub.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}


resource "google_project_service" "enable_dataflow" {
  count = var.generate_feed_files ? 1 : 0
  project = var.gcp_project
  service = "dataflow.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  depends_on    = [google_service_account.service_account,
                   ] 
}

resource "google_project_service" "enable_cloudscheduler" {
  project = var.gcp_project
  service = "cloudscheduler.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}

resource "google_project_service" "enable_datapipelines" {
  count = var.generate_feed_files ? 1 : 0
  project = var.gcp_project
  service = "datapipelines.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  depends_on    = [google_service_account.service_account,
                   ] 
}

resource "google_project_service" "enable_cloudfunctions" {
  count = var.generate_feed_files ? 1 : 0
  project = var.gcp_project
  service = "cloudfunctions.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
  depends_on    = [google_service_account.service_account,
                   ]  
}

resource "google_project_iam_member" "permissions_token" {
  project = data.google_project.project.project_id
  role   = "roles/iam.serviceAccountShortTermTokenMinter"
  member = "serviceAccount:${google_service_account.service_account.email}"
  depends_on    = [google_service_account.service_account]
  
}

resource "google_project_iam_member" "permissions_dataflow" {
  project = data.google_project.project.project_id
  role   = "roles/dataflow.worker"
  member = "serviceAccount:${google_service_account.service_account.email}"
  depends_on    = [google_service_account.service_account,
                   null_resource.generate_feed_files[0]]  
}


resource "google_project_iam_member" "permissions_gcs" {
  project = data.google_project.project.project_id
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.service_account.email}"
  depends_on    = [google_service_account.service_account,
                   null_resource.generate_feed_files]  
}

resource "google_project_iam_member" "permissions_bq_admin" {
  project = data.google_project.project.project_id
  role   = "roles/bigquery.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
  depends_on    = [google_service_account.service_account]
}



resource "google_bigquery_dataset" "zombies_dataset" {
  project = data.google_project.project.project_id
  dataset_id    = var.zombies_dataset_name
  friendly_name = var.zombies_dataset_name
  description   = "Dataset to store the zombies calculations"
  location      = var.zombies_data_location

  depends_on    = [google_project_iam_member.permissions_token,
                   google_project_iam_member.permissions_bq_admin]
}

resource "google_pubsub_topic" "zombies_bq_sq_completed_topic" {
  depends_on    = [google_project_service.enable_pubsub]
  name = var.zombies_pubsub_topic
}
