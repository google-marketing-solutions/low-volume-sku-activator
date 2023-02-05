# Zombies on Steroids
Zombies on Steroids is a solution that aims to pull out the least viewed
products on Google Shopping in order to drive them in a separate Google Ads
campaign.

This is done by leveraging BigQuery Merchant Center Data Transfers to detect
the product reactivation opportunity and generate the supplemental feeds at
scale.

This solution is perfect for retailers with millions of products in shopping,
as it will help to identify and reactivate products that are not getting the
attention they deserve.

## Prerequisites
- A Google Cloud Platform user with the Owner role.
- Terraform version >=1.3.7
- Python version >=3.8.1
- A Big Query Data Transfer of Google Merchant Center and Google Ads (you can
use [Markup](https://github.com/google/shopping-markup) to set this up)
- The pairs of Merchants IDs and Google Ads IDs you want this project to run 
on.

#### To get the pairs, you can run the following query:
```sql
SELECT
 DISTINCT(MerchantId) AS merchant_id_table_suffix,
 _TABLE_SUFFIX AS gads_id_table_suffix
FROM `<project>.<merchant_dataset>.p_ShoppingProductStats_*`
WHERE merchantId != 0
GROUP BY 1,_TABLE_SUFFIX
```
## How to deploy
- Clone this repository onto your local machine 
by running ```git clone https://github.com/google/zombies-on-steroids```
- Navigate to the project folder by running ```cd zombies_on_steroids/```
- Make sure you edit the ```variables.tf``` file with all the relevant values.
- Run ```terraform init``` to initialize the working directory.
- Then, run ```terraform plan``` to view the execution plan that Terraform will
execute.
- Finally, run ```terraform apply``` to execute the action from the plan.

## Generated Artefacts
### BigQuery Scheduled Query:

- One BigQuery scheduled query will be created for each pair with the following
naming convention: Zombie_<MC_ACCOUNT_ID>_<GADS_ACCOUNT_ID>
- The schedule is set by the config variable “zombies_schedule”
- Pubsusb topic specified by the variable “zombies_pubsub_topic” to notify 
scheduled query completion

If the config ```variable generate_feed_files``` is set to ```true```, the 
following artefacts will be generated:

- __Cloud Function:__ ```zombies_feed_generation_trigger```. Triggered by a 
PubSub message on the topic ```zombies_pubsub_topic```. The message is sent 
upon scheduled query completion.
- __Dataflow:__ a job with the following naming convention will be executed 
```zb-<MC_ACCOUNT_ID>-<GADS_ACCOUNT_ID>```
- __CSV files:__ will be stored in the corresponding GCS location indicated by 
- the ```accounts_table``` variable and with the following naming convention
```zombies_feed_<MC_ACCOUNT_ID>-<GADS_ACCOUNT_ID>.csv```

## Author
- Jaime Martinez (jaimemm@)
