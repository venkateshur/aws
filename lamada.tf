#==========================#
# SQS OF SNS SUBSCRIPTIONS #
#==========================#
resource "aws_sqs_queue" "sqs-edp-forpurpose-to-oneup" {
  name                       = "edp-sqs-rawintegration"
  receive_wait_time_seconds  = 10
  tags                       = var.required_common_tags
  kms_master_key_id          = data.aws_kms_key.eds_platform_sqs_key.id
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sqs-edp-forpurpose-to-oneup_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sns_topic_subscription" "sqs-edp-forpurpose-to-oneup_sns_subscription" {
  count = length(var.sns_subscriptions_forpurpose-to-oneup)

  topic_arn = "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:${var.sns_subscriptions_forpurpose-to-oneup[count.index]}"
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.sqs-edp-forpurpose-to-oneup.arn
}

resource "aws_sqs_queue_policy" "sqs-edp-forpurpose-to-oneup_policy" {
  count = length(var.sns_subscriptions_forpurpose-to-oneup)

  depends_on = [time_sleep.wait_60_seconds_sqs]
  queue_url  = aws_sqs_queue.sqs-edp-forpurpose-to-oneup.id

  policy = jsonencode({
    "Version" = "2012-10-17"
    "Id"      = "${aws_sqs_queue.sqs-edp-forpurpose-to-oneup.arn}/policy"
    "Statement" = [
      for topic in var.sns_subscriptions_forpurpose-to-oneup :
      {
        Sid       = "topic-subscription-${topic}"
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.sqs-edp-forpurpose-to-oneup.arn
        Condition = {
          "ArnEquals" = {
            "aws:SourceArn" : "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:${topic}"
          }
        }
      }
    ]
  })
}

#========================================#
# SQS OF SNS SUBSCRIPTIONS - DEAD LETTER #
#========================================#
resource "aws_sqs_queue" "sqs-edp-forpurpose-to-oneup_dlq" {
  name                      = "edp-sqs-rawintegration-dlq"
  receive_wait_time_seconds = 10
  tags                      = var.required_common_tags
  kms_master_key_id         = data.aws_kms_key.eds_platform_sqs_key.id
}

resource "aws_sqs_queue_policy" "sqs-edp-forpurpose-to-oneup_dlq_policy" {
  depends_on = [time_sleep.wait_60_seconds_sqs]
  queue_url  = aws_sqs_queue.sqs-edp-forpurpose-to-oneup_dlq.id

  policy = jsonencode({
    "Version" = "2012-10-17"
    "Id"      = "${aws_sqs_queue.sqs-edp-forpurpose-to-oneup_dlq.arn}/policy"
    "Statement" = [
      {
        Sid       = "dlq-subscription"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.sqs-edp-forpurpose-to-oneup_dlq.arn
        Condition = {
          "ArnEquals" = {
            "aws:SourceArn" : aws_sqs_queue.sqs-edp-forpurpose-to-oneup.arn
          }
        }
      }
    ]
  })
}

#==============================#
# SLEEP FOR SQS AND DLQ POLICY #
#==============================#
# need to sleep for 60 seconds after aws_sqs_queue - https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_SetQueueAttributes.html
resource "time_sleep" "wait_60_seconds_sqs" {
  depends_on = [
    aws_sqs_queue.sqs-edp-forpurpose-to-oneup,
    aws_sqs_queue.sqs-edp-forpurpose-to-oneup_dlq
  ]
  create_duration = "60s"
}

#========================#
# MWAA TRIGGERING LAMBDA #
#========================#
resource "aws_lambda_function" "lambda-edp-forpurpose-to-oneup" {
  depends_on = [aws_s3_bucket_object.lambda-edp-forpurpose-to-oneup_s3_zip]

  function_name    = "lambda-edp-forpurpose-to-oneup"
  handler          = "lambda_function.lambda_handler"
  memory_size      = 320
  publish          = true
  role             = aws_iam_role.lambda-edp-forpurpose-to-oneup_role.arn
  s3_bucket        = aws_s3_bucket_object.lambda-edp-forpurpose-to-oneup_s3_zip.bucket
  s3_key           = aws_s3_bucket_object.lambda-edp-forpurpose-to-oneup_s3_zip.key
  source_code_hash = filebase64sha256("lambda/lambda-raw-intg-event.zip")
  runtime          = "python3.7"

  environment {
    variables = {
      mwaa_environment_name = var.mwaa_environment_name
      env                   = var.env
    }
  }

  tags = var.required_common_tags

  vpc_config {
    security_group_ids = [aws_security_group.edp_lambda_rawintegration_sg.id]
    subnet_ids         = data.aws_subnet_ids.golden_vpc_subnets.ids
  }

}

resource "aws_lambda_event_source_mapping" "edp_lambda_rawintegration_mapping" {
  batch_size       = 1
  event_source_arn = aws_sqs_queue.sqs-edp-forpurpose-to-oneup.arn
  enabled          = true
  function_name    = aws_lambda_function.edp_lambda_rawintegration.arn
}

#============================#
# ROLE AND POLICY FOR LAMBDA #
#============================#
resource "aws_iam_role" "edp_lambda_rawintegration_role" {
  name               = "edp-lambda-rawintegration-role"
  path               = "/tf/"
  assume_role_policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "edp_lambda_rawintegration_attach_vpc_access_ingestion" {
  role       = aws_iam_role.edp_lambda_rawintegration_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "edp_lambda_rawintegration_role_policy" {
  depends_on = [time_sleep.wait_60_seconds_lambda]
  name       = "edp-lambda-rawintegration-policy"
  role       = aws_iam_role.edp_lambda_rawintegration_role.id
  policy     = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "cloudwatch:PutMetricData",
        "events:PutEvents",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "*"
      ],
      "Effect": "Allow"
    },
    {
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${aws_sqs_queue.sqs-edp-forpurpose-to-oneup.arn}",
      "Effect": "Allow"
    },
    {
      "Effect": "Allow",
      "Action": "airflow:CreateCliToken",
      "Resource": "arn:aws:airflow:us-east-1:${data.aws_caller_identity.current.account_id}:environment/eds-mwaa-integration-zone-${var.env}"
    },
    {
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "${data.aws_kms_key.eds_platform_sqs_key.arn}"
    }
  ]
}
EOF
}

#==================#
# SLEEP FOR LAMBDA #
#==================#
resource "time_sleep" "wait_60_seconds_lambda" {
  depends_on      = [aws_lambda_function.edp_lambda_rawintegration]
  create_duration = "60s"
}

#===========================#
# S3 OBJECT FOR LAMBDA CODE #
#===========================#
resource "aws_s3_bucket_object" "edp_lambda_rawintegration_s3_zip" {
  bucket = "evernorth-us-edp-${var.env}-artifacts"
  key    = "lambda/ingestions/s3_sqs_lambda_ingestion.zip"
  source = "lambda/lambda-raw-intg-event.zip"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = filemd5("./lambda/lambda-raw-intg-event.zip")
}

#===========================#
# SECURITY GROUP FOR LAMBDA #
#===========================#
resource "aws_security_group" "edp_lambda_rawintegration_sg" {
  name        = "${var.acct_abbr}-${var.project_name}-lambda"
  description = "Allow all outbound for Lambda"
  vpc_id      = data.aws_vpc.golden_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.required_common_tags
}
