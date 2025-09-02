variable "delegate_account_id" {
  description = "The ID of the AWS Account to delegate authority to."
  type        = string
  nullable    = false
}

variable "max_session_duration" {
  description = "The maximum duration that the delegate account can assume the role in this account."
  type        = string
  default     = null
}

variable "allow_group_lookup" {
  description = "Whether to allow the delegate account to look up group IDs in the Identity Store by attributes or external identifiers. This is necessary if you want to allow the delegate to assign SSO permissions based on group names or other group attributes, instead of needing to know the group's AWS Identity Store ID in advance."
  type        = bool
  default     = false
  nullable    = false
}

variable "allow_user_lookup" {
  description = "Whether to allow the delegate account to look up user IDs in the Identity Store by attributes or external identifiers. This is necessary if you want to allow the delegate to assign SSO permissions based on usernames or other user attributes, instead of needing to know the user's AWS Identity Store ID in advance."
  type        = bool
  default     = false
  nullable    = false
}
