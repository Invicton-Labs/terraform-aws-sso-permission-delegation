output "assume_role_arn_read" {
  description = "The ARN of the IAM role to assume (for read-only access) in the `aws.sso` provider that must be passed to this module."
  value       = local.assume_role_arn_read
}
output "assume_role_arn_write" {
  description = "The ARN of the IAM role to assume (for write access) in the `aws.sso` provider that must be passed to this module."
  value       = local.assume_role_arn_write
}
