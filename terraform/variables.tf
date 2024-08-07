# AWS Information
variable "aws_account_id" {
  type        = string
  description = "The 12 digit AWS account ID where the event source will be made available for an event bus."
}

variable "aws_region" {
  type        = string
  description = "The AWS region where the event source will be made available for an event bus. (e.g. us-east-1)"
}

variable "aws_event_bus_name" {
  type        = string
  description = "A unique name appended to the Event Source in the AWS account. Maximum of 64 characters consisting of lower/upper case letters, numbers, ., -, _."
}

# Genesys Cloud Information
variable "genesys_cloud_organization_id" {
  type        = string
  description = "Genesys Cloud Organization Id"
}

variable "client_id" {
  type        = string
  description = "The OAuth (Client Credentails) Client ID to be used by Data Actions"
}

variable "client_secret" {
  type        = string
  description = "The OAuth (Client Credentails) Client Secret to be used by Data Actions"
}

variable "file_name_prefix" {
  type    = string
  default = "event-bridge/transcript/conversation-"
}

variable "gen_cloud_env" {
  type    = string
  description = "The Genesys Cloud region where the event source will be made available for an event bus. (e.g. us-east-1)"
}