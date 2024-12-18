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

resource "google_bigquery_job" "product_view" {
  depends_on = [google_bigquery_table.geo_targets_table]

  for_each = { for pair in var.accounts_table : pair.mc => pair }

  job_id     = "product_view_${each.value.gads}_${each.value.mc}_${random_id.id.hex}"

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
        # Creates a snapshot of product_view.
        #
        # The Products_<Merchant Id> table has product data partitioned by date.
        # This view will get latest product data and create derived columns useful for further processing of
        # data.

        CREATE OR REPLACE VIEW `${var.gcp_project}.${var.zombies_dataset_name}.product_view_${each.value.mc}`
        AS (
        WITH
            ApprovedOffer AS (
            SELECT DISTINCT
                _PARTITIONDATE,
                product_id,
                merchant_id,
                target_country
            FROM
                `${var.gcp_merchant_and_gads_dataset_project}.${var.merchant_dataset_name}.Products_${each.value.mc}` AS Products,
                Products.destinations,
                destinations.approved_countries AS target_country
            ),
            PendingOffer AS (
            SELECT DISTINCT
                _PARTITIONDATE,
                product_id,
                merchant_id,
                target_country
            FROM
                `${var.gcp_merchant_and_gads_dataset_project}.${var.merchant_dataset_name}.Products_${each.value.mc}` AS Products,
                Products.destinations,
                destinations.pending_countries AS target_country
            ),
            DisapprovedOffer AS (
            SELECT DISTINCT
                _PARTITIONDATE,
                product_id,
                merchant_id,
                target_country
            FROM
                `${var.gcp_merchant_and_gads_dataset_project}.${var.merchant_dataset_name}.Products_${each.value.mc}` AS Products,
                Products.destinations,
                destinations.disapproved_countries AS target_country
            ),
            OfferIssue AS (
            SELECT
                _PARTITIONDATE,
                product_id,
                merchant_id,
                target_country,
                STRING_AGG(
                IF(LOWER(issues.servability) = 'disapproved', issues.short_description, NULL), ', ')
                AS disapproval_issues,
                STRING_AGG(
                IF(LOWER(issues.servability) = 'demoted', issues.short_description, NULL), ', ')
                AS demotion_issues,
                STRING_AGG(
                IF(LOWER(issues.servability) = 'unaffected', issues.short_description, NULL), ', ')
                AS warning_issues
            FROM
                `${var.gcp_merchant_and_gads_dataset_project}.${var.merchant_dataset_name}.Products_${each.value.mc}` AS Products,
                Products.issues,
                issues.applicable_countries AS target_country
            GROUP BY
                1, 2, 3, 4
            ),
            MultiChannelTable AS (
            SELECT DISTINCT
                _PARTITIONDATE,
                merchant_id,
                product_id
            FROM
                `${var.gcp_merchant_and_gads_dataset_project}.${var.merchant_dataset_name}.Products_${each.value.mc}`
            GROUP BY
                _PARTITIONDATE,
                merchant_id,
                product_id
            HAVING COUNT(DISTINCT (channel)) > 1
            ),
            LatestDate AS (
            SELECT
                MAX(_PARTITIONDATE) AS latest_date
            FROM
                `${var.gcp_merchant_and_gads_dataset_project}.${var.merchant_dataset_name}.Products_${each.value.mc}`
            ),
            ProductStatus AS (
            SELECT
                Products._PARTITIONDATE AS _DATA_DATE,
                LatestDate.latest_date AS _LATEST_DATE,
                Products.product_id,
                Products.merchant_id,
                Products.aggregator_id,
                Products.offer_id,
                Products.title,
                Products.description,
                Products.link,
                Products.mobile_link,
                Products.image_link,
                Products.additional_image_links,
                Products.content_language,
                COALESCE(
                ApprovedOffer.target_country,
                PendingOffer.target_country,
                DisapprovedOffer.target_country) AS target_country,
                Products.channel,
                Products.expiration_date,
                Products.google_expiration_date,
                Products.adult,
                Products.age_group,
                Products.availability,
                Products.availability_date,
                Products.brand,
                Products.color,
                Products.condition,
                Products.custom_labels,
                Products.gender,
                Products.gtin,
                Products.item_group_id,
                Products.material,
                Products.mpn,
                Products.pattern,
                Products.price,
                Products.sale_price,
                Products.sale_price_effective_start_date,
                Products.sale_price_effective_end_date,
                Products.google_product_category,
                Products.google_product_category_path,
                Products.product_type,
                Products.additional_product_types,
                IF(ApprovedOffer.product_id IS NULL, 0, 1) AS is_approved,
                CONCAT(CAST(Products.merchant_id AS STRING), '|', Products.product_id)
                AS unique_product_id,
                IFNULL(SPLIT(Products.product_type, '>')[SAFE_OFFSET(0)], 'N/A') AS product_type_l1,
                IFNULL(SPLIT(Products.product_type, '>')[SAFE_OFFSET(1)], 'N/A') AS product_type_l2,
                IFNULL(SPLIT(Products.product_type, '>')[SAFE_OFFSET(2)], 'N/A') AS product_type_l3,
                IFNULL(SPLIT(Products.product_type, '>')[SAFE_OFFSET(3)], 'N/A') AS product_type_l4,
                IFNULL(SPLIT(Products.product_type, '>')[SAFE_OFFSET(4)], 'N/A') AS product_type_l5,
                IFNULL(SPLIT(Products.google_product_category_path, '>')[SAFE_OFFSET(0)], 'N/A')
                AS google_product_category_l1,
                IFNULL(SPLIT(Products.google_product_category_path, '>')[SAFE_OFFSET(1)], 'N/A')
                AS google_product_category_l2,
                IFNULL(SPLIT(Products.google_product_category_path, '>')[SAFE_OFFSET(2)], 'N/A')
                AS google_product_category_l3,
                IFNULL(SPLIT(Products.google_product_category_path, '>')[SAFE_OFFSET(3)], 'N/A')
                AS google_product_category_l4,
                IFNULL(SPLIT(Products.google_product_category_path, '>')[SAFE_OFFSET(4)], 'N/A')
                AS google_product_category_l5,
                IF(Products.availability = 'in stock', 1, 0) AS in_stock,
                IF(MultiChannelTable.product_id IS NULL, 'single_channel', 'multi_channel')
                AS channel_exclusivity
            FROM
                `${var.gcp_merchant_and_gads_dataset_project}.${var.merchant_dataset_name}.Products_${each.value.mc}` AS Products,
                LatestDate
            LEFT JOIN ApprovedOffer
                USING (_PARTITIONDATE, product_id, merchant_id)
            LEFT JOIN PendingOffer
                USING (_PARTITIONDATE, product_id, merchant_id)
            LEFT JOIN DisapprovedOffer
                USING (_PARTITIONDATE, product_id, merchant_id)
            LEFT JOIN MultiChannelTable
                USING (_PARTITIONDATE, product_id, merchant_id)
            )
        SELECT
            ProductStatus.*,
            OfferIssue.disapproval_issues,
            OfferIssue.demotion_issues,
            OfferIssue.warning_issues
        FROM
            ProductStatus
        LEFT JOIN OfferIssue
            ON
            OfferIssue._PARTITIONDATE = ProductStatus._DATA_DATE
            AND OfferIssue.product_id = ProductStatus.product_id
            AND OfferIssue.merchant_id = ProductStatus.merchant_id
            AND OfferIssue.target_country = ProductStatus.target_country
        );
  EOF
  }
}