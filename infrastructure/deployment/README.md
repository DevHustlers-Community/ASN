# Deployment

Environment-specific deployment configuration and documentation.

| Environment | Purpose | Notes |
|---|---|---|
| `development/` | Local and shared dev | Compose, seeded data, permissive limits |
| `staging/` | Pre-production | Production-like config, separate credentials and data |
| `production/` | Live | Least-privilege roles, backups, alerting |

**Rules:**

- Separate configuration per environment; no secret is committed.
- A deploy runs the owning service's migrations before starting the new version,
  and migrations must be backward compatible with the previous version during
  rollout.
- Rollback is a deploy of the previous artifact plus a forward corrective
  migration, not a destructive down-migration.
- Every deploy includes a post-deploy health check and a broker lag check.
- Database backups are verified before a schema change that rewrites data.

**Status:** no deployment manifests yet; the first target is a single-host
development/staging deploy without Kubernetes.
