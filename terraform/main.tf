###################################
#####  Genesys Cloud Objects  #####
###################################

# Create EventBridge Integration
module "AwsEventBridgeIntegration" {
   source              = "git::https://github.com/GenesysCloudDevOps/aws-event-bridge-module.git?ref=main"
   integration_name    = "automated-chatbot-with-amazon-lex"
   aws_account_id      = var.aws_account_id
   aws_account_region  = var.aws_region
   event_source_suffix = var.aws_event_bus_name
   topic_filters       = ["v2.conversations.{id}.transcription"]
}

data "aws_cloudwatch_event_source" "genesys_event_bridge" {
  depends_on  = [ module.AwsEventBridgeIntegration ]
  name_prefix = "aws.partner/genesys.com/cloud/${var.genesys_cloud_organization_id}/${var.aws_event_bus_name}"
}

#########################
#####  AWS Objects  #####
#########################

# AWS EventBridge
resource "aws_cloudwatch_event_bus" "genesys_audit_event_bridge" {
  name              = data.aws_cloudwatch_event_source.genesys_event_bridge.name
  event_source_name = data.aws_cloudwatch_event_source.genesys_event_bridge.name
}

# S3 Buckets
resource "aws_s3_bucket" "raw_transcript_bucket" {
  bucket        = "genesys-raw-transcripts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "transformed_transcript_bucket" {
  bucket        = "genesys-transformed-transcripts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Functions
resource "aws_lambda_function" "read_from_eb_function" {
  filename         = "ReadFromEBandWritetoS3.zip"
  function_name    = "ReadFromEBFunction"
  role             = aws_iam_role.lambda_role.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 128

  environment {
    variables = {
      clientid     = var.client_id
      clientsecret = var.client_secret
      bucketname   = aws_s3_bucket.raw_transcript_bucket.id
      fileprefix   = var.file_name_prefix
      genesysenv   = var.gen_cloud_env
      httptimeout  = 10
    }
  }

  tracing_config {
    mode = "Active"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_function" "convert_to_lex_format" {
  filename         = "ConvertToLexFormat.zip"
  function_name    = "ConvertToLexFormat"
  role             = aws_iam_role.lambda_role.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 128

  environment {
    variables = {
      targetbucketname = aws_s3_bucket.transformed_transcript_bucket.id
    }
  }

  tracing_config {
    mode = "Active"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy" "s3_write_policy" {
  name = "s3_write_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectACL"
        ]
        Resource = [
          "${aws_s3_bucket.raw_transcript_bucket.arn}/*",
          "${aws_s3_bucket.transformed_transcript_bucket.arn}/*",
          "arn:aws:s3:::*"
        ]
      }
    ]
  })

  lifecycle {
    create_before_destroy = true
  }
}

# S3 Event Trigger
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.raw_transcript_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.convert_to_lex_format.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json"
  }

  depends_on = [
    aws_lambda_function.convert_to_lex_format,
    aws_lambda_permission.allow_s3
  ]
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "genesys_event_rule" {
  name           = "genesys-event-rule"
  description    = "EventRule"
  event_pattern  = jsonencode({
    source = ["aws.partner/genesys.com"]
  })
  event_bus_name = data.aws_cloudwatch_event_source.genesys_event_bridge.name

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [ module.AwsEventBridgeIntegration ]
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule           = aws_cloudwatch_event_rule.genesys_event_rule.name
  target_id      = "genesysEbEventRule"
  arn            = aws_lambda_function.read_from_eb_function.arn
  event_bus_name = data.aws_cloudwatch_event_source.genesys_event_bridge.name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.convert_to_lex_format.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_transcript_bucket.arn

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.read_from_eb_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.genesys_event_rule.arn}/*"

  lifecycle {
    create_before_destroy = true
  }
}

# Outputs
output "raw_transcript_bucket" {
  value       = aws_s3_bucket.raw_transcript_bucket.id
  description = "S3 Bucket for Raw Genesys Transcripts"
}

output "transformed_transcript_bucket" {
  value       = aws_s3_bucket.transformed_transcript_bucket.id
  description = "S3 destination Bucket for Transformed Genesys Transcripts"
}

output "read_from_eb_function" {
  value       = aws_lambda_function.read_from_eb_function.arn
  description = "ReadFromEBFunction function Arn"
}

output "convert_to_lex_format" {
  value       = aws_lambda_function.convert_to_lex_format.arn
  description = "ConvertToLexFormat function Arn"
}

# Data source to get the current AWS account ID
data "aws_caller_identity" "current" {}