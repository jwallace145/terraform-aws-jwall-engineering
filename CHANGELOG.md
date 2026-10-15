# Changelog

## [0.5.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.4.0...v0.5.0) (2026-10-15)


### ⚠ BREAKING CHANGES

* **site-ci-roles:** remove the moved blocks for 0.3.x role addresses ([#13](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/13))

### Bug Fixes

* **site-ci-roles:** allow cloudfront:ListTagsForResource on project functions ([#15](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/15)) ([5aab970](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/5aab97040c11d34abb81229cf8f1d344afe74163))


### Code Refactoring

* **site-ci-roles:** remove the moved blocks for 0.3.x role addresses ([#13](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/13)) ([bcc6b29](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/bcc6b299a4756e6ebb7f2d7b763a5503a5e455c8))

## [0.4.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.3.0...v0.4.0) (2026-10-15)


### Features

* **foundation:** add tfstate-bucket, hosted-zone and infra-ci-roles modules ([#11](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/11)) ([1296e2e](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/1296e2e924650b35929c3963cad2721b4670a8ac))
* **github-oidc-role:** add the github oidc role module and build site-ci-roles on it ([#10](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/10)) ([55c1516](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/55c151614659dfb7821f94b419be66b2deaa756c))

## [0.3.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.2.0...v0.3.0) (2026-10-15)


### Features

* **site-ci-roles:** trust immutable github oidc subjects via owner_id and repository_id ([#8](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/8)) ([04ad505](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/04ad505d58a5e1b471448a0dce060ffdf8f1a34a))

## [0.2.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.1.0...v0.2.0) (2026-10-15)


### Features

* add root site-stack module for the terraform registry ([#5](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/5)) ([352f59b](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/352f59b80378a6d32cc22731a64f4edcc0d93c99))

## 0.1.0 (2026-10-15)


### Features

* add context, site-bucket, site-ci-roles, static-site and preview-site modules ([3076236](https://github.com/jwallace145/terraform-library/commit/3076236652059b0f41e705a9434caedb94c07a59))
