###################################
#####  Genesys Cloud Objects  #####
###################################

# Create a custom role
resource "genesyscloud_auth_role" "transcription_role" {
  name        = "Transcription Role"
  description = "Custom Role for Transcription"
  permission_policies {
    domain      = "recording"
    entity_name = "recording"
    action_set  = ["view","viewSensitiveData"]
  }
  permission_policies {
    domain      = "recording"
    entity_name = "recordingSegment"
    action_set  = ["view"]
  }
  permission_policies {
    domain      = "speechAndTextAnalytics"
    entity_name = "data"
    action_set  = ["view"]
  }
}

# Create OAuth - Client Credentials
resource "genesyscloud_oauth_client" "example-client" {
  name                          = "Transcription OAuth Client"
  access_token_validity_seconds = 86400
  authorized_grant_type         = "CLIENT-CREDENTIALS"
  roles {
    role_id     = genesyscloud_auth_role.transcription_role.id
  }
}

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
