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
# --------------------------------------------------
# Set these before applying the configuration
# --------------------------------------------------
variable gcp_project {
  type        = string
  description = "Google Cloud Project ID where the artifacts will be deployed"
  default = "zombies-on-steroids"
}

variable gcp_region {
  type        = string
  description = "Google Cloud Region"
  default = "europe-west1"
}

variable gcp_merchant_dataset_project {
  type        = string
  description = "The Google Cloud Project ID where the merchant center data is stored"
  default = "zombies-on-steroids"
}

variable merchant_dataset_name {
  type        = string
  description = "The name of the dataset to store the results"
  default = "markup"
}

variable zombies_bucket_name {
  type        = string
  description = "Google Cloud Region"
  default = "zombies-bucket"
}

variable zombies_bucket_location {
  type        = string
  description = "Location for the bucket"
  default = "US"
}

variable zombies_sa {
  type        = string
  description = "Name for the service account without project name"
  default = "zombies-sa"
}

variable zombies_data_location {
  type        = string
  description = "Region for the zombies dataset"
  default = "US"
}

variable zombies_dataset_name {
  type        = string
  description = "The name of the dataset to store the results"
  default = "zombies"
}

variable zombies_schedule {
  type        = string
  description = "Schedule for the BQ scheduled queries"
  default = "every day 03:00"
}

variable zombies_pubsub_topic {
  type        = string
  description = "Topic to publish the pubsub message to"
  default = "zombies_ready"
}

variable zombies_optimisation {
  type        = string
  description = "clicks or impressions"
  default = "clicks"
}

variable zombies_deciles {
  type        = number
  description = "Number of deciles to calculate"
  default = 10
}

variable zombies_impressions_decil {
  type        = number
  description = "Decil to consider for impressions"
  default = 2
}

variable zombies_clicks_decil {
  type        = number
  description = "Decil to consider for clicks"
  default = 4
}

variable generate_feed_files {
  type        = bool
  description = "true or false to indicate if Dataflow and CFs must be deployed"
  default = false
}


variable accounts_table {
  type = map(object({
    mc = string,
    gads = string,
    gcs_url = string
  }))
  default ={ 
          "1" = { "mc": "123456789", "gads": "9876543210", "gcs_url": "gs://na"}
    }
}