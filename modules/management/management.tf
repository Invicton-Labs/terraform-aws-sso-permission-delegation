// Get the SSO instances
data "aws_ssoadmin_instances" "this" {}

module "assert_instances" {
  source        = "Invicton-Labs/assertion/null"
  version       = "~>0.2.7"
  condition     = length(data.aws_ssoadmin_instances.this.arns) > 0
  error_message = "No SSO instances found. Either SSO isn't managed by this account, or the wrong AWS provider is being used."
}

data "aws_caller_identity" "this" {}

// Allow the delegated account to assume the role
data "aws_iam_policy_document" "delegated_assume" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${var.delegate_account_id}:root"
      ]
    }
  }
}

locals {
  sso_instance_ids = [
    for arn in data.aws_ssoadmin_instances.this.arns :
    join("/", slice(split("/", provider::aws::arn_parse(arn).resource), 1, length(split("/", provider::aws::arn_parse(arn).resource))))
  ]
  // Actions that can be performed on the instance
  instance_actions_read = [
    "sso:DescribePermissionSetProvisioningStatus",
    "sso:DescribeAccountAssignmentCreationStatus",
    "sso:DescribeAccountAssignmentDeletionStatus",
  ]
  instance_actions_write = []
  // Actions that can be performed on the instance and permission set,
  // AND that support an aws:RequestTag condition key.
  instance_and_permission_set_request_actions_read = []
  instance_and_permission_set_request_actions_write = [
    "sso:CreatePermissionSet"
  ]
  // Actions that can be performed on the instance and permission set,
  // AND that support an aws:ResourceTag condition key.
  instance_and_permission_set_resource_actions_read = [
    "sso:ListTagsForResource",
    "sso:DescribePermissionSet",
    "sso:ListCustomerManagedPolicyReferencesInPermissionSet",
    "sso:ListManagedPoliciesInPermissionSet",
    "sso:GetInlinePolicyForPermissionSet",
    "sso:GetPermissionsBoundaryForPermissionSet",
  ]
  instance_and_permission_set_resource_actions_write = [
    "sso:UpdatePermissionSet",
    "sso:DeletePermissionSet",
    "sso:AttachCustomerManagedPolicyReferenceToPermissionSet",
    "sso:DetachCustomerManagedPolicyReferenceFromPermissionSet",
    "sso:AttachManagedPolicyToPermissionSet",
    "sso:DetachManagedPolicyFromPermissionSet",
    "sso:PutInlinePolicyToPermissionSet",
    "sso:DeleteInlinePolicyFromPermissionSet",
    "sso:DeletePermissionsBoundaryFromPermissionSet",
    "sso:PutPermissionsBoundaryToPermissionSet",
  ]
  // Actions that can be performed on the instance, the account, and the permission set,
  // AND that support an aws:ResourceTag condition key.
  instance_account_permission_resource_actions_read = [
    "sso:ListAccountAssignments",
  ]
  instance_account_permission_resource_actions_write = [
    "sso:CreateAccountAssignment",
    "sso:DeleteAccountAssignment",
    "sso:ProvisionPermissionSet",
  ]

  // All of the Instance resources to apply action permissions to
  instance_resources = data.aws_ssoadmin_instances.this.arns
  // All of the Account resources to apply action permissions to
  account_resources = [
    "arn:aws:sso:::account/${var.delegate_account_id}"
  ]
  // All of the identity store resources to apply action permissions to
  identity_store_resources = [
    for identity_store_id in data.aws_ssoadmin_instances.this.identity_store_ids :
    "arn:aws:identitystore::${data.aws_caller_identity.this.account_id}:identitystore/${identity_store_id}"
  ]
  // All of the permission set resources to apply action permissions to
  permission_set_resources = [
    for instance_id in local.sso_instance_ids :
    "arn:aws:sso:::permissionSet/${instance_id}/*"
  ]
  // A combination of all SSO instance resources and account resources to apply action permissions to
  instances_and_account_resources = concat(local.instance_resources, local.account_resources)
}

// Things that can be done in the management account as a read-only user
data "aws_iam_policy_document" "management_read" {
  // Allow listing the SSO instances. The delegate account
  // needs this to be able to get the instance IDs/ARNs.
  statement {
    actions = [
      "sso:ListInstances"
    ]
    resources = [
      "arn:aws:sso:::instance/*"
    ]
  }

  // Instance-level actions
  statement {
    actions   = local.instance_actions_read
    resources = local.instance_resources
  }

  // Permissions that require both instance and permission set resources,
  // and support the aws:RequestTag condition key.
  // This has to be split into two statements because
  // the PermissionSet resource can handle a condition key,
  // while the Instance resource cannot.
  dynamic "statement" {
    for_each = length(local.instance_and_permission_set_request_actions_read) > 0 && length(local.instance_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_and_permission_set_request_actions_read
      resources = local.instance_resources
      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }
  dynamic "statement" {
    for_each = length(local.instance_and_permission_set_request_actions_read) > 0 && length(local.permission_set_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_and_permission_set_request_actions_read
      resources = local.permission_set_resources
      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/AccountId"
        values   = [var.delegate_account_id]
      }
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }

  // Permissions that require both instance and permission set resources,
  // and support the aws:ResourceTag condition key.
  // This has to be split into two statements because
  // the PermissionSet resource can handle a condition key,
  // while the Instance resource cannot.
  dynamic "statement" {
    for_each = length(local.instance_and_permission_set_resource_actions_read) > 0 && length(local.instance_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_and_permission_set_resource_actions_read
      resources = local.instance_resources
    }
  }
  dynamic "statement" {
    for_each = length(local.instance_and_permission_set_resource_actions_read) > 0 && length(local.permission_set_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_and_permission_set_resource_actions_read
      resources = local.permission_set_resources
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }

  // Permissions that require instance, account, and permission set resources,
  // and support the aws:ResourceTag condition key.
  // This has to be split into two statements because
  // the PermissionSet resource can handle a condition key,
  // while the Instance and Account resources cannot.
  dynamic "statement" {
    for_each = length(local.instance_account_permission_resource_actions_read) > 0 && length(local.instances_and_account_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_account_permission_resource_actions_read
      resources = local.instances_and_account_resources
    }
  }
  dynamic "statement" {
    for_each = length(local.instance_account_permission_resource_actions_read) > 0 && length(local.permission_set_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_account_permission_resource_actions_read
      resources = local.permission_set_resources
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = var.allow_user_lookup ? [null] : []
    content {
      actions = [
        "sso-directory:SearchUsers"
      ]
      resources = [
        "*"
      ]
    }
  }
  dynamic "statement" {
    for_each = var.allow_user_lookup ? [null] : []
    content {
      actions = [
        "identitystore:GetUserId",
        "identitystore:DescribeUser",
      ]
      resources = concat(local.identity_store_resources, [
        "arn:aws:identitystore:::user/*"
      ])
    }
  }

  dynamic "statement" {
    for_each = var.allow_group_lookup ? [null] : []
    content {
      sid = "GroupLookup"
      actions = [
        "sso-directory:SearchGroups"
      ]
      resources = [
        "*"
      ]
    }
  }
  dynamic "statement" {
    for_each = var.allow_group_lookup ? [null] : []
    content {
      actions = [
        "identitystore:GetGroupId",
        "identitystore:DescribeGroup",
      ]
      resources = concat(local.identity_store_resources, [
        "arn:aws:identitystore:::group/*"
      ])
    }
  }
}

// Things that can be done in the management account as a write user
data "aws_iam_policy_document" "management_write" {
  source_policy_documents = [
    // The write role gets all of the read permissions
    data.aws_iam_policy_document.management_read.json,
  ]

  // Instance-level actions
  dynamic "statement" {
    for_each = length(local.instance_actions_write) > 0 && length(local.instance_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_actions_write
      resources = local.instance_resources
    }
  }

  // Permissions that require both instance and permission set resources,
  // and support the aws:RequestTag condition key.
  // This has to be split into two statements because
  // the PermissionSet resource can handle a condition key,
  // while the Instance resource cannot.
  dynamic "statement" {
    for_each = length(local.instance_and_permission_set_request_actions_write) > 0 && length(local.instance_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_and_permission_set_request_actions_write
      resources = local.instance_resources
      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }
  dynamic "statement" {
    for_each = length(local.instance_and_permission_set_request_actions_write) > 0 && length(local.permission_set_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_and_permission_set_request_actions_write
      resources = local.permission_set_resources
      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/AccountId"
        values   = [var.delegate_account_id]
      }
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }

  // Permissions that require both instance and permission set resources,
  // and support the aws:ResourceTag condition key.
  // This has to be split into two statements because
  // the PermissionSet resource can handle a condition key,
  // while the Instance resource cannot.
  dynamic "statement" {
    for_each = length(local.instance_and_permission_set_resource_actions_write) > 0 && length(local.instance_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_and_permission_set_resource_actions_write
      resources = local.instance_resources
    }
  }
  dynamic "statement" {
    for_each = length(local.instance_and_permission_set_resource_actions_write) > 0 && length(local.permission_set_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_and_permission_set_resource_actions_write
      resources = local.permission_set_resources
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }

  // Permissions that require instance, account, and permission set resources,
  // and support the aws:ResourceTag condition key.
  // This has to be split into two statements because
  // the PermissionSet resource can handle a condition key,
  // while the Instance and Account resources cannot.
  dynamic "statement" {
    for_each = length(local.instance_account_permission_resource_actions_write) > 0 && length(local.instances_and_account_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_account_permission_resource_actions_write
      resources = local.instances_and_account_resources
    }
  }
  dynamic "statement" {
    for_each = length(local.instance_account_permission_resource_actions_write) > 0 && length(local.permission_set_resources) > 0 ? [null] : []
    content {
      actions   = local.instance_account_permission_resource_actions_write
      resources = local.permission_set_resources
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }

  // Allow putting new tags on resources. This one is a bit unique
  // because it supports an aws:RequestTag condition key on the instance.
  dynamic "statement" {
    for_each = length(local.instance_resources) > 0 ? [null] : []
    content {
      actions = [
        "sso:TagResource",
      ]
      resources = local.instance_resources
      // If it's the AccountId tag that's being added, ensure it has the correct value.
      condition {
        test     = "StringEqualsIfExists"
        variable = "aws:RequestTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }
  dynamic "statement" {
    for_each = length(local.permission_set_resources) > 0 ? [null] : []
    content {
      actions = [
        "sso:TagResource",
      ]
      resources = local.permission_set_resources
      // If it's the AccountId tag that's being added, ensure it has the correct value.
      condition {
        test     = "StringEqualsIfExists"
        variable = "aws:RequestTag/AccountId"
        values   = [var.delegate_account_id]
      }
      // This can only be done on permission sets with this correct tag.
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }

  // Allow removing tags
  dynamic "statement" {
    for_each = length(local.instance_resources) > 0 ? [null] : []
    content {
      actions = [
        "sso:UntagResource",
      ]
      resources = local.instance_resources
      // Only allow removing tags OTHER than the AccountId tag
      condition {
        test     = "ForAllValues:StringNotEquals"
        variable = "aws:TagKeys"
        values   = ["AccountId"]
      }
    }
  }
  dynamic "statement" {
    for_each = length(local.permission_set_resources) > 0 ? [null] : []
    content {
      actions = [
        "sso:UntagResource",
      ]
      resources = local.permission_set_resources
      // Only allow removing tags OTHER than the AccountId tag
      condition {
        test     = "ForAllValues:StringNotEquals"
        variable = "aws:TagKeys"
        values   = ["AccountId"]
      }
      // Still restrict untagging to resources for this account
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/AccountId"
        values   = [var.delegate_account_id]
      }
    }
  }
}

resource "aws_iam_role" "delegate_read" {
  name                 = module.assert_instances.checked ? "sso-delegation-${var.delegate_account_id}-read" : null
  path                 = "/sso-delegation/"
  assume_role_policy   = data.aws_iam_policy_document.delegated_assume.json
  max_session_duration = var.max_session_duration
}

resource "aws_iam_role_policy" "delegate_read" {
  name   = "SSOManagementReadOnly"
  role   = aws_iam_role.delegate_read.id
  policy = data.aws_iam_policy_document.management_read.json
}

resource "aws_iam_role" "delegate_write" {
  name                 = module.assert_instances.checked ? "sso-delegation-${var.delegate_account_id}-write" : null
  path                 = "/sso-delegation/"
  assume_role_policy   = data.aws_iam_policy_document.delegated_assume.json
  max_session_duration = var.max_session_duration
}

resource "aws_iam_role_policy" "delegate_write" {
  name   = "SSOManagement"
  role   = aws_iam_role.delegate_write.id
  policy = data.aws_iam_policy_document.management_write.json
}
