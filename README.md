# Low volume SKUS activator

Low volume SKUS activator is a solution that aims to pull out the least viewed
products on Google Shopping in order to drive them in a separate Google Ads
campaign.

This is done by leveraging BigQuery Merchant Center Data Transfers to detect
the product reactivation opportunity and generate the supplemental feeds at
scale.

This solution is perfect for retailers with millions of products in shopping,
as it will help to identify and reactivate products that are not getting the
attention they deserve.

## Important Note

Majority of the installation script is based in Terraform and will try to create all the artefacts specified in the configuration: GCS buckets, Cloud Functions, BigQuery Datasets… if they exist you may want to import the status into Terraform prior execution.

Regarding Merchant data transfers, if this is the first time a Merchant transfer is created, it might fail during the first 24-72 hours, which is the time it takes for Merchant reporting generation process to be set up

If deploying the GAds and Merchant Bigquery Data Transfers, the Cloud user executing the script must have access granted to GAds and Merchant Center accounts

Since GAds and Merchant Data Transfers cannot be created using Terraform due to the authorization code, the resource status is not currently saved. Bear in mind that multiple runs of the script may end up duplicating the Data Transfers.

If the script fails when you run it for the first time, it might be due to delay in preparing Merchant account data. Please wait up to 1-3 days before re-running the script.

## Prerequisite

Google cloud user with privileges over all the APIs listed in the config (ideally Owner role), so it’s possible to grant some privileges to the Service Account automatically.

- Latest version of Terraform installed
- Python version >= 3.8.1 installed
- PiP installed
- Python Virtualenv installed
- List of Merchant - GAds account pairs ready (which GAds account is linked to which Merchant account)

If you already have the Merchant and GAds data into BigQuery tables by using BigQuery Data Transfers, you can extract the account pairs with the following query:

```sql
# To get the pairs, you can run the following query :

SELECT
 DISTINCT(MerchantId) AS merchant_id_table_suffix,
 _TABLE_SUFFIX AS gads_id_table_suffix
FROM `<project>.<merchant_and_gads_dataset>.p_ShoppingProductStats_*`
WHERE merchantId != 0
GROUP BY 1,_TABLE_SUFFIX
```

Otherwise you will need to compile it manually.

Roles that will be automatically  granted to the service account during the installation process:

"roles/iam.serviceAccountShortTermTokenMinter"
"roles/storage.objectAdmin"
"roles/bigquery.admin"

## How to deploy

- Clone this repository onto your local machine
by running ```git clone http://github.com/google/low_volume_skus_activator.```
- Navigate to the project folder ```cd low_volume_skus_activator/```
- Make sure you edit the ```variables.tf``` file with all the relevant values, refer to the [Updating variables.tf](#updating-variables.tf) section.
- Set cloud project: ```gcloud config set project <my-project>```
- Login with your credentials: ```gcloud auth application-default login```
- Set the environment variable GOOGLE_APPLICATION_CREDENTIALS to the generated user key file after running the command above. It says something similar to Credentials saved to file: [/usr/local/xxx/home/xxxx/.config/gcloud/application_default_credentials.json]. An example of the export command would be: export ```GOOGLE_APPLICATION_CREDENTIALS=/usr/local/xxx/home/xxxx/.config/gcloud/application_default_credentials.json```
- Open a shell, go to the root directory of the downloaded code, execute “chmod 755 create_transfers.sh deploy.sh”
- First execute “./create_transfers.sh”
- STOP HERE: Once BQ transfers are created it can take up to 3 days to see the reports in BQ. Don't go to next 
    steps until you can see the reports in BigQuery (in the datasets you sepecified in ```variables.tf```
- Once the reports have been imported, execute "./deploy.sh"
- Type “yes” and hit return every time the system asks for confirmation (2 times maximum)

## Generated Cloud Artefacts

- BigQuery Scheduled Query:

    One BigQuery scheduled query will be created for each pair with the following naming convention: Zombie_<MC_ACCOUNT_ID>_<GADS_ACCOUNT_ID>
    The schedule is set by the config variable “zombies_schedule”
    Pubsub topic specified by the variable “zombies_pubsub_topic” to notify scheduled query completion

- If the config variable create_merchant_and_gads_transfers is set to “true”, the following artefacts will be generated:

    BigQuery Data Transfer for each GAds account with the name GAds_Transfer_{gads_id}
    BigQuery Data Transfer for each Merchant account Merchant_Transfer_{mc_id}

**IMPORTANT NOTE: if this is the first time the Merchant transfer is created, it might fail during the first 24-72 hours, which is the time it takes for Merchant reporting generation process to be set up**

- If the config variable generate_feed_files is set to “true”, the following artefacts will be generated:

    Cloud Function: zombies_feed_generation. Triggered by a pubsub message  on the topic “zombies_pubsub_topic”. The message is sent upon scheduled query completion.

## Ouput

### Ouput Table

For every (mcc, gads) account pair, one sharded (YYYYMMDD) table will be generated with the following naming convention:
{gcp_project}.{zombies_dataset_name}.LowVolumeSkus_{mcc_id}_{gads_id}_*

The table fields are described below:

|Fied Name|Type|Nullable?|Description|
|:----|:----|:----|:----|
|offer_id|STRING|NULLABLE|The offer_id analysed|
|item_group_id|STRING|NULLABLE|The item_group_id of the offer_id|
|country|STRING|NULLABLE|The country|
|feed_label|STRING|NULLABLE|The label for building the feed (country)|
|offer_id_clicks|FLOAT|NULLABLE|The sum of all the clicks of the offer_id|
|offer_id_impressions|FLOAT|NULLABLE|The sum of all the impressions of the offer_id|
|group_clicks|FLOAT|NULLABLE|The sum of all the clicks in the item_group_idoup|
|group_impressions|FLOAT|NULLABLE|The sum of all the impressions in the item_group_id|
|avg_group_clicks|FLOAT|NULLABLE|The avg_clicks of all the offer_ids in the same item_group_id|
|avg_group_impressions|FLOAT|NULLABLE|The avg_impressions of all the offer_ids in the same item_group_id|
|clicks_threshold|FLOAT|NULLABLE|Distributing the clicks per country in {zombies_deciles} deciles, this indicates the value of {zombies_clicks_decil}|
|impressions_threshold|FLOAT|NULLABLE|Distributing the clicks per country in {zombies_deciles} deciles, this indicates the value of {zombies_impressions_decil}|

### Supplemental Feeds

If the config variable generate_feed_files is set to “true”, CSV files will be stored in the corresponding GCS location indicated by the “accounts_table” variable. The CSV naming convention is as follows:

zombies_feed_<MC_ACCOUNT_ID>-<GADS_ACCOUNT_ID>.csv

The fields in the CSV files are:

offer_id, item_group_id, custom_label_{zombies_feed_label_index} in TSV format.

## How to activate

### Specific Shopping Campaigns For Zombie Products

The idea is to label the zombies so they are filtered into an specific Shopping Zombies campaign with lower ROAS, to give those products a second chance (or circumvent cold start effect)

- Prepare Merchant

    Make sure the custom_label_{zombies_feed_label_index} attribute is blank for all products in each feed

    Create the supplemental feeds in Merchant Center and link the feed file GCS URL. It should be the same as the one in the configuration variable {accounts_table}

- Prepare Google Ads:

    Create Zombies Shopping campaign, and select only those products with custom_label_{zombies_feed_label_index} = ‘zombie’

- Double check Zombies solution:

    Make sure the config variable {generate_feed_files} is set to “true”. If it wasn’t you will need to change the value to “true” and run “terraform apply -parallelism=1”

Either run the zombies scheduled query manually or wait for an execution cycle and check the files are generated correctly in the right gcs locations.

### Product Insights

Here are several use cases to activate, for example:

- Products without clicks but with impressions, might lead to either a pricing problem or a poor ad position (low bidding). The query to extract those products:

```sql
SELECT offer_id, item_group_id, 'zombie' as custom_label_{zombies_feed_label_index}
        FROM `{gcp_project}.{zombies_dataset_name}.LowVolumeSkus_{mcc_id}_{gads_id}_*`
        WHERE
          _TABLE_SUFFIX = {run_date}
          AND clicks = 0 AND impressions > 0
```

- Products performing worse than group average, to take procurement decisions:

```sql
SELECT offer_id, item_group_id, 'zombie' as custom_label_{zombies_feed_label_index}
        FROM `{gcp_project}.{zombies_dataset_name}.LowVolumeSkus_{mcc_id}_{gads_id}_*`
        WHERE
          _TABLE_SUFFIX = {run_date}
          AND clicks < avg_group_clicks
```

- Super Zombie products, no impressions:

```sql
SELECT offer_id, item_group_id, 'zombie' as custom_label_{zombies_feed_label_index}
        FROM `{gcp_project}.{zombies_dataset_name}.LowVolumeSkus_{mcc_id}_{gads_id}_*`
        WHERE
          _TABLE_SUFFIX = {run_date}
          AND impressions = 0
```

- Products from a group which, as a group, perform under the country threshold:

```sql
SELECT offer_id, item_group_id, 'zombie' as custom_label_{zombies_feed_label_index}
        FROM `{gcp_project}.{zombies_dataset_name}.LowVolumeSkus_{mcc_id}_{gads_id}_*`
        WHERE
          _TABLE_SUFFIX = {run_date}
          AND group_impressions < impressions_threshold
```

## Updating variables.tf

|Fied Name|Mandatory update|Comment
|:----|:----|:----
|gcs|YES | udpate "bucket" parameter
|credentials_path|YES|
|gcp_project|YES|
|gcp_region|NO|default is EU
|gcp_merchant_and_gads_dataset_project|YES|
|create_merchant_and_gads_transfers|NO|Default is true
|merchant_dataset_name|NO|
|gads_dataset_name|NO|
|merchant_schedule|NO|
|gads_schedule|NO|
|zombies_bucket_name|YES|GCS name must be unique
|zombies_bucket_location|NO|default is EU
|zombies_sa|NO|
|zombies_data_location|NO|default is EU
|zombies_dataset_name|NO|
|zombies_schedule|NO|
|zombies_pubsub_topic|NO|
|zombies_sql_condition|NO| but check default value ...
|zombies_deciles|NO| but check default value ...
|zombies_impressions_decil|NO| but check default value ...
|zombies_clicks_decil|NO| but check default value ...
|generate_feed_files|NO| Default is true
|zombies_feed_label_index|YES| The value set might be alreadt taken
|accounts_table|YES|

## Author

- Jaime Martinez (jaimemm@)
