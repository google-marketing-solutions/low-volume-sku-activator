# Copyright 2023 Google LLC
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
# Creates a snapshot of standard shopping criteria view.
#
# The view parse the adgroup criteria into multiple columns that will used to join with the GMC data
# to find the targeted products.

resource "google_storage_bucket_object" "geo_targets_file" {
  depends_on = [google_bigquery_dataset.zombies_dataset,
                google_storage_bucket.zombies_bucket
  ]
  name   = "geo_targets.csv"
  source = "data/geo_targets.csv"
  bucket = var.zombies_bucket_name
}

resource "google_bigquery_table" "geo_targets_table" {
  depends_on = [google_storage_bucket_object.geo_targets_file
  ]
  dataset_id = google_bigquery_dataset.zombies_dataset.dataset_id
  table_id   = "geo_targets"
  
  external_data_configuration {
    autodetect    = true
    source_format = "CSV"
    csv_options {
      quote = "\""
      skip_leading_rows = 1
    }
    source_uris = [
      "gs://${var.zombies_bucket_name}/${google_storage_bucket_object.geo_targets_file.name}",
    ]
  }

  schema = <<EOF
[
  {
    "name": "criteria_id",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "The id of the criteria"
  },
  {
    "name": "name",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Name"
  },
  {
    "name": "canonical_name",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Canonical Name"
  },
  {
    "name": "parent_id",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Parent ID"
  },
  {
    "name": "country_code",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Country Code"
  },
   {
    "name": "target_type",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Target Type"
  },
   {
    "name": "status",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Status"
  }
]
EOF
}