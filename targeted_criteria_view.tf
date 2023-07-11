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

resource "google_bigquery_job" "criteria_view" {
  depends_on = [google_bigquery_job.pmax_criteria_view,
                google_bigquery_job.adgroup_criteria_view ]

  for_each = { for pair in var.accounts_table : pair.mc => pair }

  job_id = "criteria_view_${each.value.gads}_${random_id.id.hex}"

  location = var.zombies_data_location

  query {
    create_disposition = ""
    write_disposition = ""
    query = <<EOF
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
        # Creates a snapshot criteria view for both stardard & pmax campaigns.
        CREATE OR REPLACE VIEW `${var.gcp_project}.${var.zombies_dataset_name}.criteria_view_${each.value.gads}`
        AS (
        SELECT
            _DATA_DATE,
            _LATEST_DATE,
            'AdGroup' AS source,
            merchant_id,
            target_country,
            custom_label0,
            custom_label1,
            custom_label2,
            custom_label3,
            custom_label4,
            product_type_l1,
            product_type_l2,
            product_type_l3,
            product_type_l4,
            product_type_l5,
            google_product_category_l1,
            google_product_category_l2,
            google_product_category_l3,
            google_product_category_l4,
            google_product_category_l5,
            channel,
            channel_exclusivity,
            condition,
            brand,
            offer_id,
            neg_custom_label0,
            neg_custom_label1,
            neg_custom_label2,
            neg_custom_label3,
            neg_custom_label4,
            neg_product_type_l1,
            neg_product_type_l2,
            neg_product_type_l3,
            neg_product_type_l4,
            neg_product_type_l5,
            neg_google_product_category_l1,
            neg_google_product_category_l2,
            neg_google_product_category_l3,
            neg_google_product_category_l4,
            neg_google_product_category_l5,
            neg_channel,
            neg_channel_exclusivity,
            neg_condition,
            neg_brand,
            neg_offer_id
        FROM
            `${var.gcp_project}.${var.zombies_dataset_name}.adgroup_criteria_view_${each.value.gads}`
        UNION ALL
        SELECT
            _DATA_DATE,
            _LATEST_DATE,
            'pMax' AS source,
            merchant_id,
            target_country,
            custom_label0,
            custom_label1,
            custom_label2,
            custom_label3,
            custom_label4,
            product_type_l1,
            product_type_l2,
            product_type_l3,
            product_type_l4,
            product_type_l5,
            google_product_category_l1,
            google_product_category_l2,
            google_product_category_l3,
            google_product_category_l4,
            google_product_category_l5,
            channel,
            NULL AS channel_exclusivity,
            condition,
            brand,
            offer_id,
            neg_custom_label0,
            neg_custom_label1,
            neg_custom_label2,
            neg_custom_label3,
            neg_custom_label4,
            neg_product_type_l1,
            neg_product_type_l2,
            neg_product_type_l3,
            neg_product_type_l4,
            neg_product_type_l5,
            neg_google_product_category_l1,
            neg_google_product_category_l2,
            neg_google_product_category_l3,
            neg_google_product_category_l4,
            neg_google_product_category_l5,
            neg_channel,
            NULL AS neg_channel_exclusivity,
            neg_condition,
            neg_brand,
            neg_offer_id
        FROM
            `${var.gcp_project}.${var.zombies_dataset_name}.pmax_criteria_view_${each.value.gads}`
        );
  EOF
  }
}