# Security Policy

## Reporting a vulnerability

If you find a security issue in Peel, please report it privately rather than opening a
public issue. Use GitHub private vulnerability reporting:

<https://github.com/zachshallbetter/peel/security/advisories/new>

Include:

- a description of the issue and its impact,
- steps to reproduce (a minimal example is ideal),
- the affected component and version or commit.

This is a solo-maintained project. Handling is best-effort with no SLA: there is no
guaranteed response or fix time. Please give a reasonable window to ship a fix before any
public disclosure.

## Scope

This repository currently holds documentation only: the product, architecture, Finder
integration, encryption and roadmap documents and the agent contracts. It contains no
executable source. In scope are errors in those documents that would lead an implementation
to violate its own security rules: secret transport, archive path and link containment,
resource budgets, source safety and encryption claims.

## Supported versions

Peel has no releases. Only the latest commit on `main` is current.
