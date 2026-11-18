# Contributing to Peel

Thanks for your interest. Peel is at the documentation and contract stage: this repository
holds the product, architecture, Finder-integration, encryption and roadmap documents plus
the agent operating contract. It has no source tree, build or test commands yet, so a
change today is a change to those documents.

## Before you change anything

Read [README.md](README.md), [docs/status-and-roadmap.md](docs/status-and-roadmap.md) and
[docs/architecture.md](docs/architecture.md). [AGENTS.md](AGENTS.md) is the operating
contract for agents and people alike; [.agents/README.md](.agents/README.md) lists
task-specific responsibilities.

## Conventions

- Do not promote a feature from proposed to implemented, tested or qualified without source
  evidence and repeatable fixtures. Treat proposed documents as requirements, not evidence.
- Do not claim a build, test or feature works unless it was run and recorded.
- Update the README, architecture and roadmap documents in the same PR as any change in
  behavior or status.
- Commit messages use conventional prefixes, for example `docs: ...` and `chore: ...`.

## Verifying a change

There is no automated check. Re-read the links you touched, and confirm every status claim
against `docs/status-and-roadmap.md`.

## Pull requests

- Branch off `main`; keep PRs focused.
- Describe the change and how you verified it. The PR template prompts for this.
- Participation is covered by the [Code of Conduct](CODE_OF_CONDUCT.md).
