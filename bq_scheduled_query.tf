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

resource "google_bigquery_data_transfer_config" "low_volume_skus_query" {
  depends_on = [google_project_iam_member.permissions_token,
    google_project_service.enable_bqdt,
    google_pubsub_topic.zombies_bq_sq_completed_topic,
    google_bigquery_dataset.zombies_dataset
  ]
  for_each = { for pair in var.accounts_table : pair.mc => pair }

  display_name              = "low_volume_skus_${each.value.mc}_${each.value.gads}"
  location                  = var.zombies_data_location
  data_source_id            = "scheduled_query"
  schedule                  = var.zombies_schedule
  destination_dataset_id    = google_bigquery_dataset.zombies_dataset.dataset_id
  service_account_name      = google_service_account.service_account.email

  notification_pubsub_topic = google_pubsub_topic.zombies_bq_sq_completed_topic.id
  params = {
    destination_table_name_template = "LowVolumeSkus_${each.value.mc}_${each.value.gads}_{run_time|\"%Y%m%d\"}",
    write_disposition               = "WRITE_TRUNCATE",
    query                           = <<EOF
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

      WITH
        offer_ids_with_group AS (
        SELECT
          offer_id,
          item_group_id,
          feed_label
        FROM
          `${var.gcp_merchant_and_gads_dataset_project}.${var.merchant_dataset_name}.Products_${each.value.mc}`
        WHERE
          _PARTITIONDATE BETWEEN DATE_ADD(@run_date, INTERVAL -31 DAY)
          AND DATE_ADD(@run_date, INTERVAL -1 DAY)
          AND offer_id IS NOT NULL
        GROUP BY
          item_group_id,
          offer_id,
          feed_label ),
        offer_ids_with_stats AS (
        SELECT
          segments_product_item_id AS offer_id,
          SUM(metrics_clicks) AS clicks,
          SUM(metrics_impressions) AS impressions,
          GeoTargets.country_code AS country,
        FROM
          `${var.gcp_merchant_and_gads_dataset_project}.${var.gads_dataset_name}.ads_ShoppingProductStats_${each.value.gads}` AS ShoppingProductStats
        INNER JOIN
           (select distinct parent_id, country_code from `${var.gcp_project}.${var.zombies_dataset_name}.geo_targets`) AS GeoTargets
          ON
          (
              SPLIT(
              ShoppingProductStats.segments_product_country,
              '/')[
              SAFE_OFFSET(1)]
          )
          = GeoTargets.parent_id
        WHERE
          _DATA_DATE BETWEEN DATE_ADD(@run_date, INTERVAL -31 DAY)
          AND DATE_ADD(@run_date, INTERVAL -1 DAY)
          AND segments_product_item_id IS NOT NULL
        GROUP BY
          offer_id,
          country ),
        offer_ids_with_group_and_stats AS (
        SELECT
          a.*,
          b.item_group_id,
          b.feed_label
        FROM
          offer_ids_with_stats a
        LEFT JOIN
          offer_ids_with_group b
        ON
          ( LOWER(a.offer_id) = LOWER(b.offer_id) ) ),
        group_stats AS (
        SELECT
          item_group_id,
          country,
          feed_label,
          SUM(clicks) AS group_clicks,
          SUM(impressions) AS group_impressions,
          AVG(clicks) AS avg_group_clicks,
          AVG(impressions) AS avg_group_impressions
        FROM
          offer_ids_with_group_and_stats
        GROUP BY
          item_group_id,
          country,
          feed_label ),
        clicks_percentiles_by_country AS (
        SELECT
          country,
          feed_label,
          APPROX_QUANTILES(group_clicks, ${var.zombies_deciles}) percentiles
        FROM
          group_stats
        GROUP BY
          country,
          feed_label ),
        impressions_percentiles_by_country AS (
        SELECT
          country,
          feed_label,
          APPROX_QUANTILES(group_impressions, ${var.zombies_deciles}) percentiles
        FROM
          group_stats
        GROUP BY
          country,
          feed_label ),
        clicks_threshold_by_country AS (
        SELECT
          country,
          feed_label,
          MIN(percentile) AS threshold
        FROM (
          SELECT
            country,
            feed_label,
            percentiles[
          OFFSET
            (${var.zombies_clicks_decil})] AS percentile
          FROM
            clicks_percentiles_by_country )
        GROUP BY
          country,
          feed_label ),
        impressions_threshold_by_country AS (
        SELECT
          country,
          feed_label,
          MIN(percentile) AS threshold
        FROM (
          SELECT
            country,
            feed_label,
            percentiles[
          OFFSET
            (${var.zombies_impressions_decil})] AS percentile
          FROM
            impressions_percentiles_by_country )
        GROUP BY
          country,
          feed_label ),
        zombie_families AS (
        SELECT
          item_group_id,
          group_clicks,
          group_impressions,
          avg_group_clicks,
          avg_group_impressions,
          clicks_threshold,
          impressions_threshold
        FROM (
          SELECT
            fs.item_group_id AS item_group_id,
            fs.group_clicks AS group_clicks,
            fs.group_impressions AS group_impressions,
            fs.avg_group_clicks AS avg_group_clicks,
            fs.avg_group_impressions AS avg_group_impressions,
            ctc.threshold AS clicks_threshold,
            itc.threshold AS impressions_threshold,
          FROM
            group_stats fs
          LEFT JOIN
            clicks_threshold_by_country ctc
          ON
            LOWER(fs.feed_label) = LOWER(ctc.feed_label)
          LEFT JOIN
            impressions_threshold_by_country itc
          ON
            LOWER(fs.feed_label) = LOWER(itc.feed_label) ) ),
        zombie_products AS (
        SELECT
          owgs.offer_id,
          zf.item_group_id item_group_id,
          owgs.country,
          owgs.feed_label,
          owgs.clicks AS offer_id_clicks,
          owgs.impressions AS offer_id_impressions,
          zf.group_clicks group_clicks,
          zf.group_impressions group_impressions,
          zf.avg_group_clicks avg_group_clicks,
          zf.avg_group_impressions avg_group_impressions,
          zf.clicks_threshold clicks_threshold,
          zf.impressions_threshold impressions_threshold,
        FROM
          offer_ids_with_group_and_stats owgs
        RIGHT JOIN
          zombie_families zf
        ON
          LOWER(owgs.item_group_id) = LOWER(zf.item_group_id)
          AND offer_id IS NOT NULL
          AND zf.item_group_id IS NOT NULL),
      latest_targeted_products AS (
        SELECT
          SPLIT(product_id, ':')[ARRAY_LENGTH(SPLIT(product_id, ':')) - 1] as offer_id,
          target_country as country
        FROM `${var.gcp_project}.${var.zombies_dataset_name}.targeted_products_view_${each.value.gads}`
        WHERE _DATA_DATE = (SELECT MAX(_DATA_DATE) FROM `${var.gcp_project}.${var.zombies_dataset_name}.targeted_products_view_${each.value.gads}`)
      )
      SELECT
        zp.*
      FROM
        zombie_products AS zp
      INNER JOIN latest_targeted_products ltp ON
          LOWER(zp.offer_id) = LOWER(ltp.offer_id)
          AND LOWER(zp.country) = LOWER(ltp.country)
    EOF
  }
}
