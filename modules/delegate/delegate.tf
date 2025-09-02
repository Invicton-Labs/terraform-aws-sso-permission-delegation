//Get details of this delegate account
data "aws_caller_identity" "delegate" {
  provider = aws.delegate
}

// Get SSO instances in the management account
data "aws_ssoadmin_instances" "management" {
  provider = aws.management
}

module "assert_instances" {
  source        = "Invicton-Labs/assertion/null"
  version       = "~>0.2.7"
  condition     = length(data.aws_ssoadmin_instances.management.arns) > 0
  error_message = "No SSO instances found under the management provider."
}

locals {
  delegate_account_id   = data.aws_caller_identity.delegate.account_id
  instance_id           = tolist(data.aws_ssoadmin_instances.management.identity_store_ids)[0]
  instance_arn          = module.assert_instances.checked ? tolist(data.aws_ssoadmin_instances.management.arns)[0] : null
  assume_role_arn_read  = "arn:aws:iam::${var.management_account_id}:role/sso-delegation/sso-delegation-${local.delegate_account_id}-read"
  assume_role_arn_write = "arn:aws:iam::${var.management_account_id}:role/sso-delegation/sso-delegation-${local.delegate_account_id}-write"
}

resource "aws_ssoadmin_permission_set" "this" {
  provider         = aws.management
  for_each         = var.permission_sets
  name             = var.append_account_id ? "${each.key}-${local.delegate_account_id}" : each.key
  description      = each.value.description
  instance_arn     = local.instance_arn
  relay_state      = each.value.relay_state
  session_duration = each.value.session_duration
  tags = {
    AccountId = local.delegate_account_id
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  provider = aws.management
  for_each = merge([
    for ps_key, ps_value in var.permission_sets :
    {
      for idx, policy_arn in ps_value.aws_managed_policy_arns :
      "${ps_key}-${idx}" => {
        permission_set_key = ps_key
        policy_arn         = policy_arn
      }
    }
  ]...)
  instance_arn       = aws_ssoadmin_permission_set.this[each.value.permission_set_key].instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set_key].arn
  managed_policy_arn = each.value.policy_arn
}

resource "aws_ssoadmin_customer_managed_policy_attachment" "this" {
  provider = aws.management
  for_each = merge([
    for ps_key, ps_value in var.permission_sets :
    {
      for idx, policy_arn in ps_value.customer_managed_policy_arns :
      "${ps_key}-${idx}" => {
        permission_set_key = ps_key
        policy_arn         = policy_arn
      }
    }
  ]...)
  instance_arn       = aws_ssoadmin_permission_set.this[each.value.permission_set_key].instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set_key].arn
  customer_managed_policy_reference {
    // Split the ARN into its respective parts. Why this resource takes the IAM policy this way instead of taking an ARN is beyond me.
    name = split("/", provider::aws::arn_parse(each.value.policy_arn).resource)[length(split("/", provider::aws::arn_parse(each.value.policy_arn).resource)) - 1]
    path = "/${join("/", slice(split("/", provider::aws::arn_parse(each.value.policy_arn).resource), 0, length(split("/", provider::aws::arn_parse(each.value.policy_arn).resource)) - 1))}/"
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  provider = aws.management
  for_each = merge([
    for ps_key, ps_value in var.permission_sets :
    {
      for idx, policy_json in ps_value.inline_policy_jsons :
      "${ps_key}-${idx}" => {
        permission_set_key = ps_key
        policy_json        = policy_json
      }
    }
  ]...)
  instance_arn       = aws_ssoadmin_permission_set.this[each.value.permission_set_key].instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set_key].arn
  inline_policy      = each.value.policy_json
}

resource "aws_ssoadmin_permissions_boundary_attachment" "this" {
  provider = aws.management
  for_each = {
    for ps_key, ps_value in var.permission_sets :
    ps_key => ps_value
    if ps_value.permissions_boundary != null
  }
  instance_arn       = aws_ssoadmin_permission_set.this[each.key].instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn

  permissions_boundary {
    managed_policy_arn = each.value.permissions_boundary.aws_managed_policy_arn
    dynamic "customer_managed_policy_reference" {
      for_each = each.value.permissions_boundary.customer_managed_policy_arn != null ? [each.value.permissions_boundary.customer_managed_policy_arn] : []
      content {
        // Split the ARN into its respective parts. Why this resource takes the IAM policy this way instead of taking an ARN is beyond me.
        name = split("/", provider::aws::arn_parse(customer_managed_policy_reference.value).resource)[length(split("/", provider::aws::arn_parse(customer_managed_policy_reference.value).resource)) - 1]
        path = "/${join("/", slice(split("/", provider::aws::arn_parse(customer_managed_policy_reference.value).resource), 0, length(split("/", provider::aws::arn_parse(customer_managed_policy_reference.value).resource)) - 1))}/"
      }
    }
  }
}

locals {
  unique_user_lookups = distinct(flatten([
    for ps_key, ps_value in var.permission_sets :
    [
      for idx, principal_user in ps_value.principal_users :
      jsonencode(principal_user)
    ]
  ]))
  unique_group_lookups = distinct(flatten([
    for ps_key, ps_value in var.permission_sets :
    [
      for idx, principal_group in ps_value.principal_groups :
      jsonencode(principal_group)
    ]
  ]))
}

data "aws_identitystore_user" "this" {
  provider          = aws.management
  for_each          = toset(local.unique_user_lookups)
  identity_store_id = local.instance_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = jsondecode(each.key).attribute_path
      attribute_value = jsondecode(each.key).attribute_value
    }
  }
}

data "aws_identitystore_group" "this" {
  provider          = aws.management
  for_each          = toset(local.unique_group_lookups)
  identity_store_id = local.instance_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = jsondecode(each.key).attribute_path
      attribute_value = jsondecode(each.key).attribute_value
    }
  }
}

locals {
  all_principals = {
    for ps_key, ps_value in var.permission_sets :
    ps_key => concat(
      ps_value.principals,
      [
        for principal_user in ps_value.principal_users :
        {
          type = "USER"
          id   = data.aws_identitystore_user.this[jsonencode(principal_user)].id
        }
      ],
      [
        for principal_group in ps_value.principal_groups :
        {
          type = "GROUP"
          id   = data.aws_identitystore_group.this[jsonencode(principal_group)].id
        }
      ]
    )
  }
}

// Assign the account to the permission sets
resource "aws_ssoadmin_account_assignment" "this" {
  provider = aws.management
  for_each = merge([
    for ps_key, principals in local.all_principals :
    {
      for principal in principals :
      "${ps_key}-${principal.type}-${principal.id}" => {
        permission_set_key = ps_key
        principal          = principal
      }
    }
  ]...)
  instance_arn       = aws_ssoadmin_permission_set.this[each.value.permission_set_key].instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set_key].arn
  principal_id       = each.value.principal.id
  principal_type     = each.value.principal.type
  target_id          = data.aws_caller_identity.delegate.account_id
  target_type        = "AWS_ACCOUNT"
}
