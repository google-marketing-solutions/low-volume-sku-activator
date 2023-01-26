# Zombies on Steroïds
Zombies on Steroids is a solution that aims to pull out the least viewed
products on Google Shopping in order to drive them in a separate Google Ads
campaign.

This is done by leveraging BigQuery Merchant Center Data Transfers to detect
the product reactivation opportunity and generate the supplemental feeds at
scale.

This solution is perfect for retailers with millions of products in shopping,
as it will help to identify and reactivate products that are not getting the
attention they deserve.

## Prerequisite
- A Google Cloud Platform user with Owner role).
- Terraform version >=1.3.7
- Python version >=3.8.1
- A Big Query Data Transfer of Google Merchant Center and Google Ads (you can
use [Markup](https://github.com/google/shopping-markup) to set this up)
- The pairs of Merchants IDs and Google Ads IDs you want this project to run 
on.
```sql
# To get the pairs, you can run the following query :

SELECT
 DISTINCT(MerchantId) AS merchant_id_table_suffix,
 _TABLE_SUFFIX AS gads_id_table_suffix
FROM `<project>.<merchant_dataset>.p_ShoppingProductStats_*`
WHERE merchantId != 0
GROUP BY 1,_TABLE_SUFFIX
```
## How to deploy
- Clone this repository onto your local machine 
by running ```git clone http://github.com/google/zombies-on-steroids.```
- Navigate to the project folder ```cd zombies_on_steroids/```
- Make sure you edit the ```variables.tf``` file with all the relevant values.
- Run ```terraform init``` to initialize the working directory.
- Then run ```terraform plan``` to view the execution plan that Terraform will
execute.
- Finally, run ```terraform apply``` to execute the action from the plan

## Author
- Jaime Martinez (jaimemm@)