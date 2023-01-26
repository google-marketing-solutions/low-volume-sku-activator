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

resource "null_resource" "deploy_dataflow_template" {
  count = var.generate_feed_files ? 1 : 0
  depends_on            = [
        google_storage_bucket.zombies_bucket,
        google_project_service.enable_dataflow,
        google_project_service.enable_cloudscheduler,
        google_project_service.enable_datapipelines,
        google_project_iam_member.permissions_dataflow,
        google_project_iam_member.permissions_gcs,
        google_project_iam_member.permissions_bq_admin
    ]
  provisioner "local-exec" {
    command = "python3 ./src/dataflow/zombies_on_steroids_df_pipeline.py --requirements_file ./src/dataflow/requirements.txt --project ${var.gcp_project} --region ${var.gcp_region}  --template_location gs://${var.zombies_bucket_name}/dataflow/templates/zombies_on_steroids_df_pipeline --runner DataflowRunner"
  }
}


resource "null_resource" "deploy_dataflow_template_metadata" {
  count = var.generate_feed_files ? 1 : 0
  depends_on            = [
        null_resource.deploy_dataflow_template
    ]
  provisioner "local-exec" {
    command = "gsutil cp ./src/dataflow/zombies_on_steroids_df_pipeline_metadata  gs://${var.zombies_bucket_name}/dataflow/templates"
  }
}
