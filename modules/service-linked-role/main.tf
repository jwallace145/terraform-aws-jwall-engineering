# An account holds one service-linked role per AWS service (or per custom
# suffix), so this belongs in an account-level stack, once per account, never
# in a per-project one: a second project's stack would collide with the first,
# and destroying either would pull the role out from under the other.
resource "aws_iam_service_linked_role" "this" {
  aws_service_name = var.aws_service_name
  description      = var.description

  tags = {
    Component = var.component
  }

  # Hard-coded: lifecycle arguments cannot come from variables. A service
  # that is still using its role refuses the deletion anyway, and one that is
  # not would silently lose the role it launches with, so the module never
  # deletes it.
  lifecycle {
    prevent_destroy = true
  }
}
