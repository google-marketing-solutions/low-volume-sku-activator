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

import argparse
import logging

import apache_beam as beam
from apache_beam.options import pipeline_options


class ZombiesOptions(pipeline_options.PipelineOptions):
    @classmethod
    def _add_argparse_args(cls, parser):
        parser.add_value_provider_argument(
            '--gcs_destination',
            type=str,
            required=False)
        parser.add_value_provider_argument(
            '--bq_gcs_location',
            type=str,
            required=False)
        parser.add_value_provider_argument(
            '--query',
            type=str,
            required=False)


def bq_row_to_list(row):
    element = [
        str(row['clientId']),
        str(row['date']),
        str(row['gclid'])
    ]

    return element


def run(argv=None):
    parser = argparse.ArgumentParser()
    _, pipeline_args = parser.parse_known_args(argv)

    options = pipeline_options.PipelineOptions(pipeline_args)
    zombies_options = options.view_as(ZombiesOptions)
    options.view_as(pipeline_options.GoogleCloudOptions)

    logging.getLogger().setLevel(logging.INFO)

    with beam.Pipeline(options=options) as p:
        # Execute the SQL in big query and store the result data set into given Destination big query table.
        BQ_SQL_TO_TABLE = p | beam.io.ReadFromBigQuery(
            query=zombies_options.query,
            gcs_location=zombies_options.bq_gcs_location,
            use_standard_sql=True)

        BQ_VALUES = BQ_SQL_TO_TABLE | 'read values' >> beam.Map(lambda x: list(x.values()))

        BQ_CSV = BQ_VALUES | 'CSV format' >> beam.Map(
            lambda row: ', '.join(['"' + str(column) + '"' for column in row]))

        _ = (BQ_CSV | 'Write_to_GCS' >> beam.io.WriteToText(
            zombies_options.gcs_destination,
            file_name_suffix='.csv',
            num_shards='1',
            shard_name_template='',
            header='offer_id, item_group_id, custom_label_100')
             )


if __name__ == '__main__':
    # execute only if run as the entry point into the program
    run()
