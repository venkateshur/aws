import logging
import os
import boto3
import json

from s3_copy import tr


logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs_url = os.environ['SQS_URL']
sqs = boto3.client('sqs')


def delete_message(queue_url, receipt_handle):
    # Delete received message from queue
    sqs.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=receipt_handle
    )
    logger.info('Received and deleted message: %s' % message)


MessageBody = """{"bucket": "", "prefix": "","file": "*.json"}"""


def publish_message(queue_url, message_body):
    response = sqs.send_message(
        QueueUrl=queue_url,
        DelaySeconds=10,
        MessageBody=message_body)

    print(response['MessageId'])
    logger.info('Received and deleted message: %s' % message)


def subscribe_sqs(queue_url):
    try:
        response = sqs.receive_message(
            QueueUrl=queue_url,
            AttributeNames=[
                'SentTimestamp'
            ],
            MaxNumberOfMessages=1,
            MessageAttributeNames=[
                'All'
            ],
            VisibilityTimeout=0,
            WaitTimeSeconds=0
        )

        message = response['Messages'][0]
        logger.info('sns response received: ' + str(sns_response))
        return message
        #receipt_handle = message['ReceiptHandle']
        #delete_message(queue_url, receipt_handle)

    except Exception as e:
        logger.error('sqs read failed with exception: ' + str(e))
        raise e

