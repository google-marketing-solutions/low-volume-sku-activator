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


resource "google_bigquery_dataset" "merchant_and_gads_dataset" {
  count = var.create_merchant_and_gads_transfers ? 1 : 0
  project = data.google_project.project_merchant_gads.project_id
  dataset_id    = var.merchant_and_gads_dataset_name
  friendly_name = var.merchant_and_gads_dataset_name
  description   = "Dataset to store the merchant and gads calculations"
  location      = var.zombies_data_location

  depends_on    = [google_service_account.service_account,
                   google_project_iam_member.permissions_token,
                   google_project_iam_member.permissions_bq_admin,
                   google_project_service.enable_gadsapi,
                   google_project_service.enable_bqdt]
}