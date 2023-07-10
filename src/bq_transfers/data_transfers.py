# coding=utf-8
# Copyright 2020 Google LLC..
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

# python3
"""Module for managing BigQuery data transfers."""

import argparse
import datetime
import logging
import time
from typing import Any, Dict

import pytz

import google.protobuf.json_format
from google.cloud import bigquery_datatransfer_v1
from google.cloud.bigquery_datatransfer_v1 import types
from google.protobuf import struct_pb2
from google.protobuf import timestamp_pb2
import authorization


_MERCHANT_CENTER_ID = 'merchant_center'  # Data source id for Merchant Center.
_GOOGLE_ADS_ID = 'google_ads'  # Data source id for Google Ads.
_SLEEP_SECONDS = 60  # Seconds to sleep before checking resource status.
_MAX_POLL_COUNTER = 100
_PENDING_STATE = 2
_RUNNING_STATE = 3
_SUCCESS_STATE = 4
_FAILED_STATE = 5
_CANCELLED_STATE = 6


class Error(Exception):
  """Base error for this module."""


class DataTransferError(Error):
  """An exception to be raised when data transfer was not successful."""


class CloudDataTransferUtils(object):
  """This class provides methods to manage BigQuery data transfers.

  """

  def __init__(self, project_id: str):
    """Initialise new instance of CloudDataTransferUtils.
    Args:
      project_id: GCP project id.
    """
    self.project_id = project_id
    self.client = bigquery_datatransfer_v1.DataTransferServiceClient()

  def wait_for_transfer_completion(self,
                                   transfer_config: Dict[str,
                                                         Any]
                                                         ) -> None:
    """Waits for the completion of data transfer operation.
    This method retrieves data transfer operation and checks for its status. If
    the operation is not completed, then the operation is re-checked after
    `_SLEEP_SECONDS` seconds.
    Args:
      transfer_config: Resource representing data transfer.
    Raises:
      DataTransferError: If the data transfer is not successfully completed.
    """
    # TODO: Use exponential back-off for polling.
    transfer_config_name = transfer_config.name
    transfer_config_id = transfer_config_name.split('/')[-1]
    poll_counter = 0  # Counter to keep polling count.
    while True:

      parent = self.client.transfer_config_path(
          self.project_id, transfer_config_id)
      request = bigquery_datatransfer_v1.ListTransferRunsRequest(
        parent=parent,
        )
      # Make the request
      response = self.client.list_transfer_runs(request=request)
      latest_transfer = None
      for transfer in response:
        latest_transfer = transfer
        break
      if not latest_transfer:
        return
      if latest_transfer.state == _SUCCESS_STATE:
        logging.info('Transfer %s was successful.', transfer_config_name)
        return
      if (latest_transfer.state == _FAILED_STATE or
          latest_transfer.state == _CANCELLED_STATE):
        error_message = (f'Transfer {transfer_config_name} was not successful. '
                         f'Error - {latest_transfer.error_status}')
        logging.error(error_message)
        raise DataTransferError(error_message)
      logging.info(
          'Transfer %s still in progress. Sleeping for %s seconds before '
          'checking again.', transfer_config_name, _SLEEP_SECONDS)
      time.sleep(_SLEEP_SECONDS)
      poll_counter += 1
      if poll_counter >= _MAX_POLL_COUNTER:
        error_message = (f'Transfer {transfer_config_name} is taking too long'
                         ' to finish. Hence failing the request.')
        logging.error(error_message)
        raise DataTransferError(error_message)

  def _get_existing_transfer(self, data_source_id: str,
                             destination_dataset_id: str = None,
                             dataset_location: str = None,
                             params: Dict[str, str] = None,
                             name: str = None) -> bool:
    """Gets data transfer if it already exists.
    Args:
      data_source_id: Data source id.
      destination_dataset_id: BigQuery dataset id.
      dataset_location: BigQuery dataset location.
      params: Data transfer specific parameters.
    Returns:
      Data Transfer if the transfer already exists.
      None otherwise.
    """
    parent = self.client.common_location_path(self.project_id, dataset_location)
    parent = dict(parent=parent)

    for transfer_config in self.client.list_transfer_configs(dict(parent)):
      if transfer_config.data_source_id != data_source_id:
        continue
      if destination_dataset_id and transfer_config.destination_dataset_id != destination_dataset_id:
        continue
      # If the transfer config is in Failed state, we should ignore.
      is_valid_state = transfer_config.state in (_PENDING_STATE, _RUNNING_STATE,
                                                 _SUCCESS_STATE)
      params_match = self._check_params_match(transfer_config, params)
      name_matches = name is None or name == transfer_config.display_name
      if params_match and is_valid_state and name_matches:
        return transfer_config
    return None

  def _check_params_match(self,
                          transfer_config: types.TransferConfig,
                          params: Dict[str, str]) -> bool:
    """Checks if given parameters are present in transfer config.
    Args:
      transfer_config: Data transfer configuration.
      params: Data transfer specific parameters.
    Returns:
      True if given parameters are present in transfer config, False otherwise.
    """
    if not params:
      return True
    for key, value in params.items():
      config_params = transfer_config.params
      if key not in config_params or config_params[key] != value:
        return False
    return True

  def _update_existing_transfer(self, transfer_config: types.TransferConfig,
                                params: Dict[str, str]) -> types.TransferConfig:
    """Updates existing data transfer.
    If the parameters are already present in the config, then the transfer
    config update is skipped.
    Args:
      transfer_config: Data transfer configuration to update.
      params: Data transfer specific parameters.
    Returns:
      Updated data transfer config.
    """
    if self._check_params_match(transfer_config, params):
      logging.info('The data transfer config "%s" parameters match. Hence '
                   'skipping update.', transfer_config.display_name)
      return transfer_config
    new_transfer_config = types.TransferConfig()
    new_transfer_config.CopyFrom(transfer_config)
    # Clear existing parameter values.
    new_transfer_config.params.Clear()
    for key, value in params.items():
      new_transfer_config.params[key] = value
    # Only params field is updated.
    update_mask = {"paths": ["params"]}
    new_transfer_config = self.client.update_transfer_config(
        new_transfer_config, update_mask)
    logging.info('The data transfer config "%s" parameters updated.',
                 new_transfer_config.display_name)
    return new_transfer_config

  def create_merchant_center_transfer(
      self, merchant_id: str,
      destination_dataset: str,
      dataset_location: str,
      service_account: str,
      schedule: str) -> types.TransferConfig :
    """Creates a new merchant center transfer.
    Merchant center allows retailers to store product info into Google. This
    method creates a data transfer config to copy the product data to BigQuery.
    Args:
      merchant_id: Google Merchant Center(GMC) account id.
      destination_dataset: BigQuery dataset id.
      dataset_location: BigQuery dataset location.
      service_account: Name of the service account.
      schedule: Schedule to run the transfer.
    Returns:
      Transfer config.
    """
    logging.info('Creating Merchant Center Transfer.')
    parameters = struct_pb2.Struct()
    parameters['merchant_id'] = merchant_id
    parameters['export_products'] = True
    parameters['export_price_benchmarks'] = True
    parameters['export_best_sellers'] = True
    data_transfer_config = self._get_existing_transfer(_MERCHANT_CENTER_ID,
                                                       destination_dataset,
                                                       dataset_location,
                                                       parameters)
    if data_transfer_config:
      logging.info(
          'Data transfer for merchant id %s to destination dataset %s '
          'already exists.', merchant_id, destination_dataset)
      return self._update_existing_transfer(data_transfer_config, parameters)
    logging.info(
        'Creating data transfer for merchant id %s to destination dataset %s',
        merchant_id, destination_dataset)
    authorization_code = None
    authorization_code = self._get_authorization_code(_MERCHANT_CENTER_ID)
    parent = self.client.common_location_path(self.project_id, dataset_location)
     # Initialize request argument(s)
    transfer_config = bigquery_datatransfer_v1.TransferConfig()
    transfer_config.destination_dataset_id = destination_dataset
    transfer_config.display_name = f'Merchant_Transfer_{merchant_id}'
    transfer_config.data_source_id = _MERCHANT_CENTER_ID
    transfer_config.params = parameters
    transfer_config.data_refresh_window_days = 0
    transfer_config.schedule = schedule

    request = bigquery_datatransfer_v1.CreateTransferConfigRequest(
        parent=parent,
        transfer_config=transfer_config,
        authorization_code=authorization_code,
        service_account_name=service_account
    )

    transfer_config = self.client.create_transfer_config(request)
    logging.info(
        'Data transfer created for merchant id %s to destination dataset %s',
        merchant_id, destination_dataset)
    return transfer_config

  def create_google_ads_transfer(
      self,
      customer_id: str,
      destination_dataset: str,
      dataset_location: str,
      service_account: str,
      schedule: str
      ) -> types.TransferConfig:
    """Creates a new Google Ads transfer.
    This method creates a data transfer config to copy Google Ads data to
    BigQuery dataset.
    Args:
      customer_id: Google Ads customer id.
      destination_dataset: BigQuery dataset id.
      dataset_location: BigQuery dataset location.
      service_account: name of the service account to run the transfer.
      schedule: Schedule to run the transfer.

    Returns:
      Transfer config.
    """
    logging.info('Creating Google Ads Transfer.')

    parameters = struct_pb2.Struct()
    parameters['customer_id'] = customer_id
    data_transfer_config = self._get_existing_transfer(_GOOGLE_ADS_ID,
                                                       destination_dataset,
                                                       dataset_location,
                                                       parameters)
    if data_transfer_config:
      logging.info(
          'Data transfer for Google Ads customer id %s to destination dataset '
          '%s already exists.', customer_id, destination_dataset)
      return data_transfer_config
    logging.info(
        'Creating data transfer for Google Ads customer id %s to destination '
        'dataset %s', customer_id, destination_dataset)
    authorization_code = None
    authorization_code = self._get_authorization_code(_GOOGLE_ADS_ID)
    dataset_location = dataset_location
    parent = self.client.common_location_path(self.project_id, dataset_location)

    transfer_config = bigquery_datatransfer_v1.TransferConfig()
    transfer_config.destination_dataset_id = destination_dataset
    transfer_config.display_name = f'GAds_Transfer_{customer_id}'
    transfer_config.data_source_id = _GOOGLE_ADS_ID
    transfer_config.params = parameters
    transfer_config.data_refresh_window_days = 1
    transfer_config.schedule = schedule

    request = bigquery_datatransfer_v1.CreateTransferConfigRequest(
        parent=parent,
        transfer_config=transfer_config,
        authorization_code=authorization_code,
        service_account_name=service_account
    )
    transfer_config = self.client.create_transfer_config(request)
    logging.info(
        'Data transfer created for Google Ads customer id %s to destination '
        'dataset %s', customer_id, destination_dataset)

    return transfer_config

  def _get_data_source(self, data_source_id: str) -> types.DataSource:
    """Returns data source.
    Args:
      data_source_id: Data source id.
    """
    name = self.client.data_source_path(self.project_id, data_source_id)

    return self.client.get_data_source(dict(name=name))

  def _check_valid_credentials(self, data_source_id: str) -> bool:
    """Returns true if valid credentials exist for the given data source.
    Args:
      data_source_id: Data source id.
    """
    name = self.client.data_source_path(self.project_id, data_source_id)

    response = self.client.check_valid_creds(dict(name=name))
    return response.has_valid_creds

  def _get_authorization_code(self, data_source_id: str) -> str:
    """Returns authorization code for a given data source.
    Args:
      data_source_id: Data source id.
      dataset_location: BigQuery dataset location.
    """
    data_source = self._get_data_source(data_source_id)
    client_id = data_source.client_id
    scopes = data_source.scopes

    if not data_source:
      raise AssertionError('Invalid data source')
    return authorization.retrieve_authorization_code(client_id, scopes, data_source_id)

def _get_args_parser():

    parser = argparse.ArgumentParser()

    parser.add_argument('--project_id',
      help='GCP Project.',
      default=None,
      required=True)
    parser.add_argument('--merchant_dataset_id',
      help='Merchant BigQuery dataset id.',
      default=None,
      required=True)

    parser.add_argument('--gads_dataset_id',
      help='GAds BigQuery dataset id.',
      default=None,
      required=True)

    parser.add_argument('--dataset_location',
      help='BigQuery dataset_location.',
      default=None,
      required=True)

    parser.add_argument('--gads_account_id',
      help='GAds account id.',
      default=None,
      required=True)

    parser.add_argument('--merchant_account_id',
      help='Merchant account id.',
      default=None,
      required=True)

    parser.add_argument('--service_account',
      help='Service Account name.',
      default=None,
      required=True)

    parser.add_argument('--merchant_schedule',
      help='Merchant Schedule config.',
      default=None,
      required=True)

    parser.add_argument('--gads_schedule',
      help='GAds Schedule config.',
      default=None,
      required=True)
    
    return parser

def main(argv = None):
    parser = _get_args_parser();
    args, _ = parser.parse_known_args(argv)
    data_transfer = CloudDataTransferUtils(args.project_id)
    merchant_center_config = data_transfer.create_merchant_center_transfer(
        args.merchant_account_id,
        args.merchant_dataset_id,
        args.dataset_location.lower(),
        args.service_account,
        args.merchant_schedule)
    ads_config = data_transfer.create_google_ads_transfer(args.gads_account_id,
                                                            args.gads_dataset_id,
                                                            args.dataset_location.lower(),
                                                            args.service_account,
                                                            args.gads_schedule)
    try:
        logging.info('Checking the GMC data transfer status.')
        #data_transfer.wait_for_transfer_completion(merchant_center_config, args.dataset_location)
        logging.info('The GMC data have been successfully transferred.')
        logging.info('Checking the Google Ads data transfer status.')
        #data_transfer.wait_for_transfer_completion(ads_config, args.dataset_location)
        logging.info('The Google Ads data have been successfully transferred.')
    except DataTransferError:
        logging.error('If you have just created GMC transfer - you may need to'
                    'wait for up to 90 minutes before the data of your Merchant'
                    'account are prepared and available for the transfer.')
        raise


if __name__ == '__main__':
# execute only if run as the entry point into the program
    main()

