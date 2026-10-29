# Changelog

## [0.11.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.10.1...v0.11.0) (2026-10-29)


### Features

* **container-instance:** pin the instance image with ami_id ([#33](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/33)) ([1043e67](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/1043e67e40ee37d962769a02a30896436b77bdb7))

## [0.10.1](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.10.0...v0.10.1) (2026-10-28)


### Bug Fixes

* **ci-policies:** let container/read refresh the records bucket and read bot logs ([#31](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/31)) ([e54216b](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/e54216b6119f66aed6bb216a175de05d8895fee8))

## [0.10.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.9.1...v0.10.0) (2026-10-28)


### Features

* add vpc, private-bucket, container-instance and container CI policies ([#29](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/29)) ([61490a0](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/61490a0f4a05ec3caf102bf978395be768b3c935))

## [0.9.1](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.9.0...v0.9.1) (2026-10-19)


### Bug Fixes

* **hosted-zone:** pass TXT values bare so the provider's quoting is not doubled ([#27](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/27)) ([a34a4fd](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/a34a4fdef9a5b65abaa6dcb25e4e40d325122a08))

## [0.9.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.8.1...v0.9.0) (2026-10-19)


### Features

* **hosted-zone:** add txt_records for zone-owner TXT records such as domain verification ([#25](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/25)) ([aed86ee](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/aed86eee367ed43d838a9eea4920f43c3baa548c))

## [0.8.1](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.8.0...v0.8.1) (2026-10-16)


### Bug Fixes

* **ci-policies:** keep the foundation policy descriptions unchanged ([#22](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/22)) ([a53d077](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/a53d077a40f959d5278479c21b793c6c3ae78620))

## [0.8.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.7.0...v0.8.0) (2026-10-16)


### Features

* **ci-policies:** add ecr-repository and the ecr/pull and ecr/push policies ([#20](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/20)) ([3321248](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/3321248ce2938fad38ca789839e4d5339b6d1e3e))

## [0.7.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.6.0...v0.7.0) (2026-10-15)


### Features

* **buckets:** harden the state and site bucket policies against unlisted principals ([#18](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/18)) ([c3a1059](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/c3a1059cfc0b6bb978a07f064712c411800f24fa))

## [0.6.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.5.0...v0.6.0) (2026-10-15)


### ⚠ BREAKING CHANGES

* **ci-roles:** replace site-ci-roles and infra-ci-roles with per-role modules and a policy catalog ([#16](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/16))

### Features

* **ci-roles:** replace site-ci-roles and infra-ci-roles with per-role modules and a policy catalog ([#16](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/16)) ([a10353e](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/a10353eb88fd111e8356f40f8ca100a43051588f))

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
