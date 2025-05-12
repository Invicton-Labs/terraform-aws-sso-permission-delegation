variable "permission_sets" {
  type = map(object({
    description                  = optional(string)
    relay_state                  = optional(string)
    session_duration             = optional(string)
    aws_managed_policy_arns      = optional(list(string), [])
    customer_managed_policy_arns = optional(list(string), [])
    permissions_boundary = optional(object({
      aws_managed_policy_arn      = optional(string)
      customer_managed_policy_arn = optional(string)
    }))
    inline_policy_jsons = optional(list(string), [])
    principals = optional(list(object({
      id   = string
      type = string
    })), [])
    principal_groups = optional(list(object({
      attribute_path  = string
      attribute_value = string
    })), [])
    principal_users = optional(list(object({
      attribute_path  = string
      attribute_value = string
    })), [])
  }))
}

variable "management_account_id" {
  description = "The ID of the AWS account that manages AWS Identity Center (SSO)."
  type        = string
  nullable    = false
}

variable "append_account_id" {
  description = "Whether to append the delegate account ID to the permission set names. Since permission set names must be unique across the organization, this helps prevent conflicts. If you don't use this, and there is a conflict, Terraform will try to create the permission set for a very, very long time before eventually timing out."
  type        = bool
  default     = true
  nullable    = false
}
