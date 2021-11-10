import logging
import os
import boto3
import json

from s3_copy import file_transfer
from s3_copy import file_transfer
from subscribe_sqs import subscribe_sqs
from publish_sns_notification import publish_sns


logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs_url = os.environ['SQS_URL']
sqs = boto3.client('sqs')
sns_client = boto3.client('sns')

topic_arn = os.environ['SNS_TOPIC_ARN']
source_s3_bucket = os.environ['SOURCE_BUCKET']
target_s3_bucket = os.environ['TARGET_BUCKET']


def lambda_handler(event, context):
    try:
        message = subscribe_sqs(queue_url=sqs_url)
        message_dict = json.load(message)
        file_transfer(source_s3_bucket, target_s3_bucket, message_dict['key'])
        publish_sns(topic_arn, subject = "", message = "", message_attr = "", sns_client = sns_client)
    except Exception as err:
        logger.error("Error occurred while handling the event, ExceptionTrace=%s" % err)
        traceback.print_exc()