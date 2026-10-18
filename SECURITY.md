# Security Policy

## Reporting a Vulnerability

The security of Arabian Social Network (ASN) and its users is important to us.

If you discover a security vulnerability or a sensitive issue, please report it privately via email only.

**Security Contact:** [hasanmo3080vr@gmail.com](mailto:hasanmo3080vr@gmail.com)

Do not disclose security vulnerabilities through public GitHub Issues, Pull Requests, Discussions, or other public channels.

## What to Report

Please report any issue that could compromise the security, privacy, integrity, or availability of ASN, including:

- Authentication or authorization vulnerabilities.
- Account takeover or privilege escalation.
- SQL injection, command injection, or other injection vulnerabilities.
- Cross-site scripting (XSS), cross-site request forgery (CSRF), or similar web vulnerabilities.
- Insecure session management or token handling.
- Exposure of private messages, personal information, credentials, or other sensitive data.
- Insecure file uploads or unauthorized file access.
- Server-side request forgery (SSRF).
- Remote code execution.
- Insecure inter-service communication or access control.
- Data isolation failures between users, groups, tenants, or services.
- Denial-of-service vulnerabilities with a meaningful security impact.
- Vulnerable dependencies or insecure default configurations.

This list is not exhaustive. If you believe an issue has a genuine security impact, please report it.

## What to Include in Your Report

To help us investigate efficiently, please include as much of the following information as possible:

1. A clear description of the vulnerability.
2. The affected component, service, endpoint, or repository version.
3. The potential impact and affected security boundaries.
4. Reproduction steps or a proof of concept, if available.
5. Relevant logs, screenshots, or other supporting evidence.
6. Suggested mitigations, if known.

Do not include real user data, passwords, private keys, access tokens, or unrelated secrets in your report.

## Response and Remediation

Security reports are handled by authorized project maintainers.

We will make reasonable efforts to:

1. Review the report and assess its severity.
2. Investigate and reproduce the reported issue where possible.
3. Determine the affected components and potential impact.
4. Develop and test an appropriate fix or mitigation.
5. Coordinate disclosure and release information when appropriate.

Response and remediation times may vary depending on the severity, complexity, and available resources.

Please allow the maintainers reasonable time to investigate and address the issue before disclosing it publicly.

## Responsible Disclosure

Please do not publicly disclose an unpatched vulnerability or publish exploit details that could put ASN users or infrastructure at risk.

Do not access, modify, delete, or expose other people's data while investigating a suspected vulnerability.

Do not perform destructive testing, denial-of-service attacks, or testing against infrastructure you do not own or have explicit permission to assess.

Good-faith security research should be limited to the minimum activity necessary to demonstrate the issue safely.

## Scope

This policy applies to the ASN source code and project-managed components.

Third-party services, dependencies, deployments, or infrastructure may be outside the direct control of the ASN maintainers. Reports involving these components will be assessed based on their relationship to ASN and the maintainers' ability to address them.

## Supported Versions

During early development, security fixes are generally prioritized for the current maintained version and the active code in the `main` branch.

The maintainers may publish more specific version support information as the project matures.

## Security Updates

Security fixes and advisories may be published once the maintainers determine that disclosure is appropriate and affected users have had a reasonable opportunity to update.

Public disclosures will avoid exposing unnecessary exploit details that could put users at risk.

## Contact

For all security vulnerabilities and sensitive security-related issues, contact:

**Email:** [hasanmo3080vr@gmail.com](mailto:hasanmo3080vr@gmail.com)

Email is the only accepted reporting channel for sensitive security issues.

Thank you for helping keep Arabian Social Network and its users safe.
