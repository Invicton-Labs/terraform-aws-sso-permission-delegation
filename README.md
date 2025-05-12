# Terraform AWS SSO Permission Delegation
This module allows delegation of SSO permission management for a given AWS Organizations account to that account itself. This is extremely useful because it allows each organization account to manage SSO permissions for itself, without having to manage that separately from the management (SSO) account.

It achieves this by creating an IAM role in the SSO management account that has extremely strict permissions, allowing the role to create an assign permission sets as long as the permission set is tagged with the account ID of the delegate account. This prevents assigning permission sets that weren't created by the delegate account. There are many other condition keys that ensure that the role for the delegate account can only tag with its own account ID, can never delete or modify that tag, and can never add or modify tags of other permission sets.

This module consists of two sub-modules: one to be deployed in the management account (the account that manages IAM Identity Center), and one to be deployed in the delegate account.

## Usage

### Management Account

This is the configuration for the AWS account that manages IAM Identity Center.

```
module "delegated_sso_management" {
  // Note that double slash in the path to the sub-module
  source = "Invicton-Labs/aws-sso-permission-delegation/terraform//management"
  // The ID of the account that you want to allow to manage SSO permissions for itself
  delegate_account_id = "222222222222"
  // Whether the delegate account should be able to look up user and group IDs in the identity store
  allow_group_lookup  = true
  allow_user_lookup   = true
}
```

### Delegate Account

This is the configuration for the AWS account that permissions are being delegated to. Since it needs an AWS provider that assumes a specific role in the management account, and you likely have specific provider configurations that the module cannot read, this is achieved by using an output from the module to specify the role to be assumed, then passing that provider back into the module.

```
// Create the necessary providers
// This one is for this (delegate) account
provider "aws" {
  alias   = "delegate"
  region  = "my-sso-region"
  profile = "MyCompany_DelegateAccount"
}
// This one is for the management account
provider "aws" {
  alias   = "management"
  region  = "my-sso-region"
  profile = "MyCompany_ManagementAccount"
  assume_role {
    // Assume the role as specified by the module below.
    // Yes, we can do this circular thing, it works fine.
    role_arn = module.delegated_sso_delegate.assume_role_arn
  }
}

module "delegated_sso_delegate" {
  // Note that double slash in the path to the sub-module
  source = "Invicton-Labs/aws-sso-permission-delegation/terraform//delegate"
  providers = {
    aws.delegate   = aws.delegate
    aws.management = aws.management
  }
  // You can't use the Management provider with the `aws_caller_identity` data source to
  // get this, since this value is used to create the ARN that is passed out to the provider.
  management_account_id = "111111111111"

  // The permission sets and who should get to use them. The module allows passing in
  // multiple, but you can also use multiple instances of the module with just one permission
  // set passed into each, if it's easier for your configuration layout.
  permission_sets = {
    // The keys become the permission set names
    "ps-name" = {
      description = "Sample permission set!"

      // Optionally, specify AWS-managed IAM policies that should be attached to the permission set
      aws_managed_policy_arns = [
        "arn:aws:iam::aws:policy/AlexaForBusinessDeviceSetup",
      ]

      // Optionally, specify customer-managed IAM policies that should be attached to the permission set.
      // The policy has to exist in the SSO management account, NOT the delegated account.
      // That is outside of the scope of this module.
      customer_managed_policy_arns = [
        "arn:aws:iam::aws:policy/AlexaForBusinessDeviceSetup",
      ]

      // JSON-encoded IAM policy documents that should be attached to the permission set
      inline_policy_jsons = [
        data.aws_iam_policy_document.example.json
      ]

      // Optionally, set a permissions boundary
      permissions_boundary = {
        // Can use this, OR the `aws_managed_policy_arn` field, but not both.
        // Using the customer-managed option will require the policy to have been created
        // in the SSO management account, NOT in the delegated account. That is outside of
        // the scope of this module.
        customer_managed_policy_arn = aws_iam_policy.test.arn
      }

      // Specify principals that can use this permission set using their IDs
      // (no extra permissions required)
      principals = [
        {
          id   = "4ced9548-00b1-70ae-aa34-8ab5ce964cbd"
          type = "GROUP"
        }
      ]

      // Specify principal groups that can use this permission set using attributes
      // (requires the `allow_group_lookup` variable on the management side to be `true`)
      principal_groups = [
        {
          attribute_path  = "DisplayName"
          attribute_value = "Database Administrators"
        }
      ]

      // Specify principal users that can use this permission set using attributes
      // (requires the `allow_user_lookup` variable on the management side to be `true`)
      principal_users = [
        {
          attribute_path  = "UserName"
          attribute_value = "kotowick@invictonlabs.com"
        }
      ]
    }
  }
}
```
