import logging
import os
import boto3
import traceback
import re
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

actual_current_datetime = datetime.now()
current_datetime = actual_current_datetime.strftime('%Y%m%d%H%M%S')


def get_files_to_copy(bucket_name, prefix, s3_client):
    print("bucket name: " + bucket_name)
    print("prefix: " + prefix)
    return s3_client.list_objects_v2(Bucket=bucket_name, Prefix=prefix, MaxKeys=20000).get('Contents', None)


def perform_copy(s3_client, s3_contents, source_bucket, target_bucket):
    try:
        if s3_contents:
            for key in s3_contents:
                source_file = key['Key']
                copy_source = {'Bucket': source_bucket, 'Key': source_file}
                target_destination = {'Bucket': target_bucket, 'Key': source_file}
                logger.info("copying source: " + str(copy_source) + " to destination " + str(target_destination))
                s3_client.copy_object(CopySource=copy_source, Bucket=target_bucket, Key=source_file, ServerSideEncryption='aws:kms', SSEKMSKeyId= os.environ['KEY_ID'])
                s3_client.delete_object(Bucket=source_bucket, Key=source_file)
        else:
            print("Empty response received, no files found to copy")
            logger.info("No files found to copy")
    except Exception as e:
        print(e.response['Error']['Message'])
        raise e


def file_transfer(source_s3_bucket, target_s3_bucket, source_prefix):
    try:
        s3_client = boto3.client("s3")
        response = get_files_to_backup(source_s3_bucket, source_prefix, s3_client)
        perform_copy(s3_client, response, source_s3_bucket, target_s3_bucket)
    except Exception as err:
        logger.error("Error occurred while handling the event, ExceptionTrace=%s" % err)
        traceback.print_exc()