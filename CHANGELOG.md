# Changelog

## [0.24.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.23.0...v0.24.0) (2026-11-16)


### ⚠ BREAKING CHANGES

* replace databricks-shared-dataset with databricks-dataset and databricks-dataset-access ([#69](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/69))

### Features

* replace databricks-shared-dataset with databricks-dataset and databricks-dataset-access ([#69](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/69)) ([46ae3e7](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/46ae3e75e605eae1449bce16f260c6ca8ab66e1c))

## [0.23.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.22.0...v0.23.0) (2026-11-16)


### Features

* **identity-center-access:** add one person's Identity Center access as a module ([#67](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/67)) ([02c0a1b](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/02c0a1b52c8138a4b11fbf44f49a572e9fce70b6))

## [0.22.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.21.0...v0.22.0) (2026-11-15)


### Features

* **container-instance:** run the instance on a daily UTC schedule with a graceful drain ([#65](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/65)) ([570412b](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/570412b5094cefb6158fea0fdc9ad1c4fe683806))

## [0.21.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.20.0...v0.21.0) (2026-11-15)


### Features

* **databricks:** share read-only datasets across workspaces through a serverless host ([#63](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/63)) ([7a62688](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/7a6268873ffbaa715ffaae1893923a088fd79281))

## [0.20.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.19.2...v0.20.0) (2026-11-15)


### ⚠ BREAKING CHANGES

* **databricks:** stop managing system schemas and built-in users, drop the catalog URL slash ([#61](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/61))

### Bug Fixes

* **databricks:** stop managing system schemas and built-in users, drop the catalog URL slash ([#61](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/61)) ([1a60eda](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/1a60edab9ac0a3c38b9ffb971bfe0f8652ccadca))

## [0.19.2](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.19.1...v0.19.2) (2026-11-15)


### Bug Fixes

* **databricks-audit-logs:** drop ListBucketMultipartUploads so S3 accepts the prefix condition ([#59](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/59)) ([11d90bd](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/11d90bd000d0f15d1bdbe4a95a7c6a614b4b6bfa))

## [0.19.1](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.19.0...v0.19.1) (2026-11-15)


### Bug Fixes

* **databricks-audit-logs:** grant ListMultipartUploadParts on objects so S3 accepts the policy ([#57](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/57)) ([093d0f2](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/093d0f2f223c05d827cab1c154fd7380631a208b))

## [0.19.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.18.1...v0.19.0) (2026-11-14)


### Features

* **ci-policies:** let databricks/read read the EC2 vCPU quota ([#55](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/55)) ([7841e19](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/7841e195909aad563df8f9b0c84d15b44befcd0d))

## [0.18.1](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.18.0...v0.18.1) (2026-11-14)


### Bug Fixes

* **databricks-workspace-config:** take policy definitions as JSON strings ([#53](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/53)) ([f83caae](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/f83caae9040838a7213f0e68d02ad616f5b0f0c0))

## [0.18.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.17.0...v0.18.0) (2026-11-14)


### Features

* add nat-instance, vpc private subnets and the Databricks workspace modules ([#51](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/51)) ([dec1c22](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/dec1c225f666349411580ba9d16951d202bcd290))

## [0.17.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.16.1...v0.17.0) (2026-11-04)


### Features

* add research project support to dataset, task-runner and CI policy modules ([#49](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/49)) ([1b15c6b](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/1b15c6b73ba3107fd32523fe1c27fb3b3e33249d))

## [0.16.1](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.16.0...v0.16.1) (2026-10-30)


### Bug Fixes

* **task-runner:** keep the cpu profile's role and template descriptions ([#47](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/47)) ([b24978f](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/b24978fa75b124d96f3ed1c655ede07a4900d448))

## [0.16.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.15.0...v0.16.0) (2026-10-30)


### Features

* add task profiles and sub-prefix dataset grants for GPU tasks ([#45](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/45)) ([f4ba3a1](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/f4ba3a1859405f4c9dcae1ae18324d4cb5c957ce))

## [0.15.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.14.0...v0.15.0) (2026-10-30)


### Features

* **context:** tag resources ManagedBy=jwall-engineering-infra ([#43](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/43)) ([4a8ad2b](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/4a8ad2ba06a0333d4e9d29648851d0f9174b14a8))

## [0.14.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.13.0...v0.14.0) (2026-10-30)


### Features

* add dataset-bucket and the dataset CI policies ([#41](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/41)) ([cb7ef8a](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/cb7ef8a41a7371cefceed5f4b223d6740d387055))

## [0.13.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.12.1...v0.13.0) (2026-10-30)


### Features

* spot task launches, per-instance task results and six-zone VPCs ([#39](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/39)) ([899d6cc](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/899d6cc70543d972d5fa4fd5c4c268aefb2328d2))

## [0.12.1](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.12.0...v0.12.1) (2026-10-29)


### Bug Fixes

* **ci-task-role:** allow sessions that outlast the longest task ([#37](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/37)) ([5d36de5](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/5d36de507e1bad036c70ecc356e3aaa357787dba))

## [0.12.0](https://github.com/jwallace145/terraform-aws-jwall-engineering/compare/v0.11.0...v0.12.0) (2026-10-29)


### Features

* add task-runner, ci-task-role and the task CI policies ([#35](https://github.com/jwallace145/terraform-aws-jwall-engineering/issues/35)) ([585e569](https://github.com/jwallace145/terraform-aws-jwall-engineering/commit/585e569175637a519ca92f320860a4330bddad1a))

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
