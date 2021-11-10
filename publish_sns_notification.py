import logging
import os
import boto3
import json


logger = logging.getLogger()
logger.setLevel(logging.INFO)


def publish_sns(topic_arn, subject, message, message_attr, sns_client):
    try:
        sns_response = sns_client.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=message,
            MessageAttributes=message_attr

        )
        logger.info('sns response received: ' + str(sns_response))
    except Exception as e:
        raise SNSCallError(e)
