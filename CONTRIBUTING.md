# Contributing to Arabian Social Network (ASN)

Thank you for your interest in contributing to Arabian Social Network (ASN).

This document explains our contribution workflow, development process, code review policy, release management, and security reporting procedures.

Our goal is to maintain a collaborative, organized, and reliable development process while keeping the project maintainable as it grows.

## 1. Contribution Workflow

ASN follows a fork-based contribution workflow.

All contributors must work in their own forks of the repository. The official repository is the source of truth, and all contributions must be submitted through Pull Requests.

### Step 1: Find or Propose an Issue

Before starting work:

1. Browse existing GitHub Issues to avoid duplicate work.
2. Choose an open issue that matches your interests and skills.
3. Comment on the issue to express your interest.
4. Wait for approval from a project maintainer before starting substantial implementation.

For new features, architectural changes, or breaking changes, open an issue and discuss the proposed approach with the maintainers before implementation.

Small documentation improvements and obvious typo corrections may be submitted without a prior issue.

An issue being open does not automatically mean that its implementation has been approved.

### Step 2: Fork the Repository

Create a fork of the official repository under your own GitHub account.

Clone your fork:

```bash
git clone https://github.com/<your-username>/<repository>.git
cd <repository>
```

Add the official repository as an upstream remote:

```bash
git remote add upstream https://github.com/<organization>/<repository>.git
```

Verify your remotes:

```bash
git remote -v
```

Replace the placeholders with the actual repository information.

### Step 3: Create a Branch

Create a separate branch for each issue or logically independent contribution.

Use the following naming conventions:

- `feature/<issue-number>-short-description`
- `fix/<issue-number>-short-description`
- `docs/<issue-number>-short-description`
- `refactor/<issue-number>-short-description`
- `test/<issue-number>-short-description`
- `chore/<issue-number>-short-description`

Example:

```bash
git switch -c feature/42-realtime-messaging
```

Do not develop directly on `main`.

Keep unrelated changes in separate branches and Pull Requests. A branch should address one issue or one clearly defined unit of work.

### Step 4: Develop and Test

Before submitting your changes:

1. Read the relevant documentation and existing implementation.
2. Follow the project's established architecture and coding conventions.
3. Keep changes focused on the approved issue.
4. Add or update tests where applicable.
5. Run relevant tests, formatters, linters, and other available checks.
6. Update documentation when behavior, configuration, or public interfaces change.
7. Add or update a change record under [`docs/changelog/`](docs/changelog/README.md).
8. Enable the repository hooks once per clone:

   ```bash
   bash scripts/dev/install-git-hooks.sh
   ```

Do not include unrelated refactoring, secrets, credentials, personal configuration files, or generated files that should not be tracked.

If implementation reveals a need to expand the issue's scope, discuss the change with a maintainer before proceeding.

### Step 5: Commit Your Changes

Use clear and descriptive commit messages.

We recommend Conventional Commits:

- `feat: add community channels`
- `fix: prevent duplicate message delivery`
- `docs: clarify local development setup`
- `refactor: simplify connection management`
- `test: cover message ordering`
- `chore: update dependencies`

Reference the related issue when appropriate.

Every commit that changes repository content must include a change record in the
same commit and a `Changelog:` trailer:

```text
Changelog: docs/changelog/2026-10-22-governance-and-changelog.md
```

The record filename uses `YYYY-MM-DD-short-slug.md` and must match the format in
[`docs/changelog/README.md`](docs/changelog/README.md). Merge commits and commits
that only edit `docs/changelog/` are exempt. Platform-created squash commits are
exempt from the trailer; their pull request commits were already checked. Do not
rewrite or delete merged records.

Prefer small, logical commits over large commits containing unrelated changes.

### Step 6: Open a Pull Request

Push your branch to your fork:

```bash
git push -u origin feature/42-realtime-messaging
```

Open a Pull Request from your fork's branch into the official repository's `main` branch.

Every Pull Request should include:

- A clear summary of the changes.
- The related issue, using `Closes #42` when applicable.
- The motivation behind the change.
- The change record path and the `Changelog:` commit trailer.
- Tests performed and their results.
- Screenshots or examples for user-facing changes, when relevant.
- Any migration, compatibility, security, or configuration considerations.

Keep Pull Requests focused and reasonably small.

Large architectural changes must be discussed with the project maintainers before substantial implementation begins.

Do not include confidential vulnerability details in a public Pull Request. Sensitive security issues must be reported by email only, as described in the Security section.

### Step 7: Review and Merge

Only authorized project maintainers are responsible for reviewing, approving, and merging Pull Requests into the official repository.

Contributors must not merge their own Pull Requests.

A Pull Request may be merged when:

- Its purpose and scope are clear.
- Required automated checks pass, including the governance change-record check.
- Relevant tests pass.
- Review feedback has been addressed.
- No blocking discussions remain.
- An authorized maintainer approves the changes.

Maintainers may request revisions, reject a contribution, or close a Pull Request if it does not align with the project's goals, architecture, security requirements, or quality standards.

Approval does not guarantee that a change will be included in a specific release.

## 2. Development Stages

Contributions follow these stages:

### Stage 1: Proposed

An issue or feature proposal is created and discussed.

The team clarifies the problem, expected behavior, scope, and technical approach.

### Stage 2: Accepted

A project maintainer approves the proposed work.

The issue may be assigned to a contributor or opened for community contributions.

### Stage 3: In Progress

The contributor implements the approved changes in their own fork and branch.

Changes to the agreed scope should be discussed with a maintainer before implementation.

### Stage 4: Review

The contributor opens a Pull Request targeting `main`.

Maintainers review correctness, maintainability, tests, security implications, and compatibility.

Requested changes must be addressed before approval.

### Stage 5: Merged

An authorized maintainer merges the approved Pull Request into `main`.

Merged code becomes part of the official repository but is not necessarily part of an official release.

### Stage 6: Released

An authorized maintainer prepares and publishes an official release after the release criteria have been satisfied.

Only authorized project maintainers may create official releases and publish official release tags.

## 3. Branching Strategy

ASN uses a single permanent branch:

- `main`: the official development branch and the source of truth for the project.

All contributors work in their own forks using short-lived topic branches.

All Pull Requests must target `main`.

We do not use a permanent `develop` branch at this stage.

Maintainers may create temporary branches for release preparation or urgent fixes when necessary. These branches do not change the single-permanent-branch policy.

The official `main` branch must be protected against direct pushes and unauthorized merges.

## 4. Release Policy

Official releases are managed exclusively by authorized project maintainers.

We follow Semantic Versioning:

`MAJOR.MINOR.PATCH`

- **MAJOR:** incompatible changes to documented public interfaces or behavior.
- **MINOR:** backward-compatible functionality additions.
- **PATCH:** backward-compatible bug fixes.

Pre-release versions may use identifiers such as:

- `0.1.0-alpha.1`
- `0.1.0-beta.1`
- `0.1.0-rc.1`

Before publishing a release, maintainers should:

1. Review the changes intended for the release.
2. Run the required tests and regression checks.
3. Review relevant security and dependency changes.
4. Verify migration and upgrade instructions.
5. Aggregate the release's change records into `CHANGELOG.md` and write user-facing release notes.
6. Update version information where applicable.
7. Create the official version tag and GitHub Release.
8. Document known issues and relevant upgrade considerations.

A merged Pull Request does not automatically trigger an official release.

Contributors must not publish official releases or create official release tags on behalf of the project.

## 5. Hotfixes

Critical availability, security, or data-integrity issues may require an expedited workflow.

Maintainers may authorize a temporary hotfix branch when necessary.

Hotfixes must receive appropriate review and testing before being merged and released.

After a hotfix, maintainers must ensure the fix remains present in `main`.

Security vulnerabilities must be reported privately by email only, following the instructions in the Security section.

## 6. Coding Standards

All contributors are expected to:

- Follow the conventions of the language and component being modified.
- Prefer readable, maintainable solutions over unnecessary complexity.
- Avoid introducing dependencies without a clear justification.
- Handle errors and failure scenarios explicitly.
- Consider concurrency, data integrity, authentication, authorization, and input validation where relevant.
- Add tests for new behavior and bug fixes where practical.
- Keep interfaces consistent with the existing architecture.
- Document significant architectural decisions when necessary.

Do not introduce breaking changes without prior discussion and maintainer approval.

## 7. Architecture and Design Changes

Changes affecting service boundaries, communication protocols, data models, persistence, authentication, authorization, or deployment must be discussed with maintainers before substantial implementation.

Architectural proposals should explain:

- The problem being solved.
- The proposed solution.
- Alternatives considered.
- Expected operational and maintenance costs.
- Security and compatibility implications.
- Migration requirements, if any.

Maintainers may request an Architecture Decision Record (ADR) for significant architectural decisions.

## 8. Security

Never commit passwords, API tokens, private keys, production credentials, or sensitive user data.

Do not weaken authentication, authorization, validation, encryption, or other security controls to make a test pass.

### Reporting Sensitive Issues

Sensitive issues must be reported via email only.

This includes, but is not limited to:

- Security vulnerabilities.
- Authentication or authorization weaknesses.
- Potential data exposure or privacy violations.
- Privilege escalation.
- Sensitive information disclosure.
- Vulnerabilities that could compromise users, services, or infrastructure.

**Security Contact:** [hasanmo3080vr@gmail.com](mailto:hasanmo3080vr@gmail.com)

Do not report sensitive issues through public GitHub Issues, Pull Requests, Discussions, or other public channels.

When reporting a sensitive issue, include:

1. A clear description of the issue.
2. Its potential impact and affected components.
3. Reproduction steps, if available.
4. Relevant logs or supporting evidence, provided they do not expose unrelated sensitive information.
5. Any suggested mitigation, if known.

Please allow the project maintainers reasonable time to investigate and address the issue before disclosing it publicly.

Do not include real user data, passwords, private keys, or unrelated secrets in the report.

## 9. Community Guidelines

Be respectful, constructive, and professional.

Technical disagreements are welcome. Personal attacks, harassment, and discriminatory behavior are not.

Review code and ideas on their technical merits, and provide actionable feedback.

Contributors are expected to respect agreed issue scopes, review decisions, and project policies.

## 10. Change Records and Changelog

Every content commit has one record in [`docs/changelog/`](docs/changelog/README.md).
The record states what changed, why, and what was verified. It is the source for
release notes and review context.

- Name the file `YYYY-MM-DD-short-slug.md` and match the UTC commit date.
- Include the required front matter from the folder README.
- Add the `Changelog:` trailer to the commit message.
- Never put secrets, plaintext chat content, private keys, real user data, or
  exploit details in a record.
- Do not delete merged records; correct them with a follow-up record.

At release time, maintainers aggregate the records into
[`CHANGELOG.md`](CHANGELOG.md). The architecture document remains a description of
the current design and must not accumulate change history.

## 11. Questions

If you are unsure where to start, ask in the relevant issue or discussion before beginning a large implementation.

Small, focused contributions are welcome.

Thank you for helping build Arabian Social Network.
