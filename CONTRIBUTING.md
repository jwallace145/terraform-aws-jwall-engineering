# Contributing

`terraform-aws-jwall-engineering` is the versioned Terraform module library for the
jwall-engineering static sites. It follows the shared jwall-engineering repo
conventions, which are summarised here. Coding agents should read
[AGENTS.md](AGENTS.md).

## Local development setup

Requirements: Terraform `>= 1.11`, [tflint](https://github.com/terraform-linters/tflint),
[terraform-docs](https://terraform-docs.io), Node.js 24, [pre-commit](https://pre-commit.com),
and the GitHub CLI (`gh`).

```sh
git clone https://github.com/jwallace145/terraform-aws-jwall-engineering.git
cd terraform-aws-jwall-engineering
npm ci                                                          # commitlint
pre-commit install --hook-type commit-msg --hook-type pre-commit # local hooks
tflint --init --config "$PWD/.tflint.hcl"                       # AWS ruleset
```

The `commit-msg` hook runs commitlint locally. The `pre-commit` hooks run
`terraform fmt`, `terraform validate`, `tflint` and `terraform-docs`. These are
conveniences only; **CI is the authoritative check**.

Run the full CI suite locally before opening a PR:

```sh
terraform fmt -check -recursive
# Every module, including the nested ci-policies leaves.
for m in . $(find modules -name versions.tf -not -path '*/examples/*' -not -path '*/.terraform/*' -exec dirname {} \; | sort); do
  (cd "$m" && terraform init -backend=false && terraform validate \
    && tflint --config "$OLDPWD/.tflint.hcl" && terraform test)
done
for m in . $(find modules -name versions.tf -not -path '*/examples/*' -not -path '*/.terraform/*' -exec dirname {} \; | sort); do terraform-docs "$m"; done && git diff --exit-code
npm run test:commitlint
```

No AWS credentials are needed. Tests use `terraform test` with a mocked AWS
provider.

## Commits

Each commit message is a **single-line** Conventional Commit:

```
type(scope)?: subject
```

- At most 100 characters.
- Allowed types: `feat`, `fix`, `docs`, `chore`, `refactor`, `ci`, `build`,
  `perf`, `style`, `test`, `revert`.
- Breaking changes are marked with `!`, for example `feat!: rename output`.
- The **only** content allowed after the header is a blank line followed by
  `Co-authored-by: Name <email>` trailers. No body text. Details belong in the
  PR description.

This is enforced by commitlint (`@commitlint/config-conventional` plus the
local `only-coauthor-trailers` rule in `commitlint/`). The fixtures in
`tests/commitlint/` show accepted and rejected messages and are checked in CI.

## Pull requests

- After the initial scaffold commit, **every change reaches `main` through a
  PR**. Direct pushes are blocked.
- Merges are **squash or rebase only**. No merge commits; history is linear.
- The **PR title must be a valid Conventional Commit** because a squash merge
  uses it as the commit message.
- Use the typed PR template for your change and fill in every section:

  ```sh
  gh pr create --template feat.md      # or fix.md, docs.md, chore.md, refactor.md, ci.md
  ```

  In the browser, append `?template=<type>.md` to the compare URL. `fix.md`
  additionally asks for Bug, Root cause and Reproduction.
- CI runs on every PR:
  - `commitlint` over every commit in the PR range (`base..head`), so
    rebase-merged commits are all checked
  - `pr-title`, the PR title linted as a commit header
  - `commitlint-rules`, the fixture tests for the rules above
  - `fmt`, `terraform fmt -check -recursive`
  - `terraform (<module>)` per module: `init -backend=false`, `validate`,
    `tflint` with the AWS ruleset, `terraform test`, and a terraform-docs
    diff check, for both the module and its `examples/basic` (the
    `ci-policies` leaves have no example)
- All of these are required status checks on `main`.

## Module standards

- Layout: `modules/<name>/` with `main.tf`, `variables.tf`, `outputs.tf`,
  `versions.tf`, `README.md`, `examples/basic/`, `tests/`. The policy leaves
  under `modules/ci-policies/<family>/<name>/` are internal and have no
  `examples/basic/`; `modules/ci-policies/README.md` explains how to add one.
  The repo root is itself a module (the site stack) with the same layout and
  is checked the same way; the Terraform Registry publishes it as
  `jwallace145/jwall-engineering/aws` with the others as submodules.
- `required_version = ">= 1.11"`, AWS provider `~> 6.0`. Modules never
  configure providers.
- Everything runs in `us-east-1`. Modules that create CloudFront or ACM
  resources have a precondition that the current region is `us-east-1`.
- Every input has a `description` and a `type`, with `validation` blocks for
  values with a known shape.
- Every resource-creating module tags its resources with
  `Component = "<module-name>"`. All other tags come from the caller's
  provider `default_tags` (fed by the `context` module).
- `README.md` is generated with terraform-docs (`terraform-docs modules/<name>`).
  CI fails if the committed docs differ from the generated ones.
- Tests use `terraform test` with `mock_provider "aws"`.

## Releases and versioning

Releases are managed by [Release Please](https://github.com/googleapis/release-please).

- One version for the whole repository (`release-type: simple`), tagged
  `vX.Y.Z`. Release Please owns `CHANGELOG.md` and `version.txt`.
- On every push to `main`, the `release-please` workflow opens or updates a
  release PR authored by `jwallace145-release-bot[bot]`. CI runs on it like
  any other PR.
- **Merging the Release Please PR is the deliberate, human-reviewed act that
  releases a new version.** Nobody creates tags by hand.
- Every tag is picked up by the public Terraform Registry, where the repo is
  published as [`jwallace145/jwall-engineering/aws`](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest)
  (the registry requires the `terraform-<provider>-<name>` repo name). The
  registry is linked to the `jwallace145` public namespace in HCP Terraform;
  publishing happens through its GitHub webhook, nothing in CI. Consumers pin
  a version:

  ```hcl
  source  = "jwallace145/jwall-engineering/aws//modules/<name>"
  version = "X.Y.Z"
  ```

  or the git source with the same tag:

  ```hcl
  source = "git::https://github.com/jwallace145/terraform-aws-jwall-engineering.git//modules/<name>?ref=vX.Y.Z"
  ```

### Semver policy

The version is derived from commit types:

| Change | Commit type | Bump |
|---|---|---|
| Any breaking change to a module's inputs or outputs (rename, remove, change type or default, change a resource name that forces replacement) | `feat!` / `fix!` | major (minor while `0.x`) |
| New module, new optional input, new output | `feat` | minor |
| Behaviour fix that keeps inputs/outputs compatible | `fix` | patch |
| `docs`, `chore`, `ci`, `refactor`, `test`, `style`, `build` | no release on their own |

While the library is on `0.x`, a breaking change bumps the minor version
(`bump-minor-pre-major`). Breaking changes must still be marked `!` so the
changelog calls them out.

## Repository settings

Settings applied through the GitHub API (see the conventions):

- Squash and rebase merges only; squash commits use the PR title and a blank
  body. Head branches are deleted after merge.
- A ruleset on `main` requires a PR, squash/rebase merges, all CI jobs as
  status checks, linear history, and blocks force pushes and deletion, with no
  bypass actors.
