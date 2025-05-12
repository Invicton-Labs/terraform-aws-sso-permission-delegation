output "assume_role_arn" {
  description = "The ARN of the IAM role to assume in the `aws.sso` provider that must be passed to this module."
  value       = local.assume_role_arn
}
