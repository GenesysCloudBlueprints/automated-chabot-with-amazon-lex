###################################
#####  Genesys Cloud Objects  #####
###################################

# Create EventBridge Integration
module "AwsEventBridgeIntegration" {
   source              = "git::https://github.com/GenesysCloudDevOps/aws-event-bridge-module.git?ref=main"
   integration_name    = "aaa-eventbridge-poc"
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

# AWS SAM
module "lambda_function_ConvertToLexFormat" {
  source        = "terraform-aws-modules/lambda/aws"
  version       = "~> 6.0"
  timeout       = 300
  source_path   = "./src/ConvertToLexFormat/"
  function_name = "ConvertToLexFormat"
  handler       = "app.lambda_handler"
  runtime       = "python3.9"
  create_sam_metadata = true
  publish       = true
}

module "lambda_function_ReadFromEBandWritetoS3" {
  source        = "terraform-aws-modules/lambda/aws"
  version       = "~> 6.0"
  timeout       = 300
  source_path   = "./src/ReadFromEBandWritetoS3/"
  function_name = "ReadFromEBandWritetoS3"
  handler       = "app.lambda_handler"
  runtime       = "python3.9"
  create_sam_metadata = true
  publish       = true
}