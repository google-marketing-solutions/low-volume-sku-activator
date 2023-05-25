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
    query                           = "-- Copyright 2023 Google LLC.\n--\n-- Licensed under the Apache License, Version 2.0 (the \"License\");\n-- you may not use this file except in compliance with the License.\n-- You may obtain a copy of the License at\n--\n--     http://www.apache.org/licenses/LICENSE-2.0\n--\n-- Unless required by applicable law or agreed to in writing, software\n-- distributed under the License is distributed on an \"AS IS\" BASIS,\n-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\n-- See the License for the specific language governing permissions and\n-- limitations under the License.\n\nWITH\n  offer_ids_with_group AS (\n  SELECT\n    offer_id,\n    item_group_id,\n    feed_label\n  FROM\n    `${var.gcp_merchant_and_gads_dataset_project}.${var.merchant_dataset_name}.Products_${each.value.mc}`\n  WHERE\n    _PARTITIONDATE BETWEEN DATE_ADD(@run_date, INTERVAL -31 DAY)\n    AND DATE_ADD(@run_date, INTERVAL -1 DAY)\n    AND offer_id IS NOT NULL\n  GROUP BY\n    item_group_id,\n    offer_id,\n    feed_label ),\n  offer_ids_with_stats AS (\n  SELECT\n    CountryCriteriaId AS country,\n    OfferId AS offer_id,\n    SUM(clicks) AS clicks,\n    SUM(impressions) AS impressions,\n  FROM\n    `${var.gcp_merchant_and_gads_dataset_project}.${var.gads_dataset_name}.ShoppingProductStats_${each.value.gads}`\n  WHERE\n    _DATA_DATE BETWEEN DATE_ADD(@run_date, INTERVAL -31 DAY)\n    AND DATE_ADD(@run_date, INTERVAL -1 DAY)\n    AND OfferId IS NOT NULL\n  GROUP BY\n    offer_id,\n    country ),\n  offer_ids_with_group_and_stats AS (\n  SELECT\n    a.*,\n    b.item_group_id,\n    b.feed_label\n  FROM\n    offer_ids_with_stats a\n  LEFT JOIN\n    offer_ids_with_group b\n  ON\n    ( LOWER(a.offer_id) = LOWER(b.offer_id) ) ),\n  group_stats AS (\n  SELECT\n    item_group_id,\n    country,\n    feed_label,\n    SUM(clicks) AS group_clicks,\n    SUM(impressions) AS group_impressions,\n    AVG(clicks) AS avg_group_clicks,\n    AVG(impressions) AS avg_group_impressions\n  FROM\n    offer_ids_with_group_and_stats\n  GROUP BY\n    item_group_id,\n    country,\n    feed_label ),\n  clicks_percentiles_by_country AS (\n  SELECT\n    country,\n    feed_label,\n    APPROX_QUANTILES(group_clicks, ${var.zombies_deciles}) percentiles\n  FROM\n    group_stats\n  GROUP BY\n    country,\n    feed_label ),\n  impressions_percentiles_by_country AS (\n  SELECT\n    country,\n    feed_label,\n    APPROX_QUANTILES(group_impressions, ${var.zombies_deciles}) percentiles\n  FROM\n    group_stats\n  GROUP BY\n    country,\n    feed_label ),\n  clicks_threshold_by_country AS (\n  SELECT\n    country,\n    feed_label,\n    MIN(percentile) AS threshold\n  FROM (\n    SELECT\n      country,\n      feed_label,\n      percentiles[\n    OFFSET\n      (${var.zombies_clicks_decil})] AS percentile\n    FROM\n      clicks_percentiles_by_country )\n  GROUP BY\n    country,\n    feed_label ),\n  impressions_threshold_by_country AS (\n  SELECT\n    country,\n    feed_label,\n    MIN(percentile) AS threshold\n  FROM (\n    SELECT\n      country,\n      feed_label,\n      percentiles[\n    OFFSET\n      (${var.zombies_impressions_decil})] AS percentile\n    FROM\n      impressions_percentiles_by_country )\n  GROUP BY\n    country,\n    feed_label ),\n  zombie_families AS (\n  SELECT\n    item_group_id,\n    group_clicks,\n    group_impressions,\n    avg_group_clicks,\n    avg_group_impressions,\n    clicks_threshold,\n    impressions_threshold\n  FROM (\n    SELECT\n      fs.item_group_id AS item_group_id,\n      fs.group_clicks AS group_clicks,\n      fs.group_impressions AS group_impressions,\n      fs.avg_group_clicks AS avg_group_clicks,\n      fs.avg_group_impressions AS avg_group_impressions,\n      ctc.threshold AS clicks_threshold,\n      itc.threshold AS impressions_threshold,\n    FROM\n      group_stats fs\n    LEFT JOIN\n      clicks_threshold_by_country ctc\n    ON\n      fs.feed_label = ctc.feed_label\n    LEFT JOIN\n      impressions_threshold_by_country itc\n    ON\n      fs.feed_label = itc.feed_label ) ),\n  zombie_products AS (\n  SELECT\n    owgs.offer_id,\n    zf.item_group_id item_group_id,\n    owgs.country,\n    owgs.feed_label,\n    owgs.clicks AS offer_id_clicks,\n    owgs.impressions AS offer_id_impressions,\n    zf.group_clicks group_clicks,\n    zf.group_impressions group_impressions,\n    zf.avg_group_clicks avg_group_clicks,\n    zf.avg_group_impressions avg_group_impressions,\n    zf.clicks_threshold clicks_threshold,\n    zf.impressions_threshold impressions_threshold,\n  FROM\n    offer_ids_with_group_and_stats owgs\n  RIGHT JOIN\n    zombie_families zf\n  ON\n    owgs.item_group_id = zf.item_group_id\n    AND offer_id IS NOT NULL\n    AND zf.item_group_id IS NOT NULL)\nSELECT\n  zp.*\nFROM\n  zombie_products AS zp"
  }
}