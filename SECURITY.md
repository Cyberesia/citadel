# Security Policy

## Supported versions

| Version | Supported |
| :-- | :--: |
| Latest release | Yes |
| `main` branch | Yes |
| Older releases | Best effort |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Instead, report privately to the maintainers:

- **Email:** security@cyberesia.com *(preferred)*
- **GitHub:** use [Private vulnerability reporting](https://github.com/Cyberesia/citadel/security/advisories/new) if enabled on the repository

Include:

- A clear description of the issue and impact
- Steps to reproduce
- Affected versions or commits
- Any suggested fix, if you have one

We aim to acknowledge reports within **5 business days** and will coordinate disclosure once a fix is available.

## Scope

In scope:

- Citadel app, CitadelHelper, and CitadelNetExt
- Network filter, firewall rules, and privileged helper behavior
- CoworkCore integration and local agent tooling shipped with Citadel

Out of scope:

- Third-party MCP servers, skills, or agent CLIs configured by users
- Issues in upstream projects (AionCore, mlx-swift, etc.) — report those upstream

## Safe harbor

We appreciate responsible disclosure and will not pursue legal action against researchers who follow this policy in good faith.
