from typing import Optional

import boto3
import logging
import os
import traceback

SECRET_NAME_SMARTSHEET_ACCESS_TOKEN = os.environ["SECRET_NAME_SMARTSHEET_ACCESS_TOKEN"]
SECRET_PREFIX = os.environ["SECRET_PREFIX"]

logger = logging.getLogger(__name__)

# Create a Secrets Manager client
region_name = os.environ["AWS_REGION"]
session = boto3.session.Session()
client = session.client(service_name="secretsmanager", region_name = region_name)

def get_secret(secret_name: str) -> Optional[str]:
    secret = None
    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    except Exception:
        logger.error("Unexpected error fetching secret {}. Exception: {}".format(secret_name, traceback.format_exc()))
    else:
        if "SecretString" in get_secret_value_response:
            secret = get_secret_value_response["SecretString"]
    
    return secret

def create_secret(secret_name: str, secret_value: str):
    try:
        client.create_secret(
            Name=secret_name,
            SecretString=secret_value
        )
    except Exception:
        logger.error("Unexpected error creating secret {}. Exception: {}".format(secret_name, traceback.format_exc()))