# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records for Maple Key Music Academy development and deployment infrastructure.

## What are ADRs?

Architecture Decision Records document significant architectural choices made in the project, including:
- The context and problem being addressed
- Alternatives considered
- The decision made and why
- Consequences (positive, negative, and neutral)
- When to revisit the decision

ADRs help maintain project knowledge, onboard new team members, and provide interview preparation material by documenting the "why" behind architectural choices.

## Decision Log

| ADR | Title | Status | Date | Tags |
|-----|-------|--------|------|------|
| [DK-0001](DK-0001-docker-based-development.md) | Docker-Based Development Environment | Accepted | 2024-08-15 | #docker #developer-experience #deployment #scalability |

## How to Create a New ADR

### When to Create an ADR

Create an ADR whenever you make a significant decision about:
- **Development environment** (e.g., switching from Docker to Vagrant)
- **Deployment strategies** (e.g., adding Kubernetes, serverless)
- **CI/CD pipelines** (e.g., GitHub Actions vs CircleCI)
- **Infrastructure** (e.g., cloud provider choice, CDN setup)
- **Monitoring/logging** (e.g., adding Datadog, Sentry)
- **Database hosting** (e.g., managed PostgreSQL vs self-hosted)

### Workflow

1. **Copy the template:** `cp TEMPLATE.md DK-XXXX-your-decision-title.md`
2. **Number sequentially:** Use the next available number (DK-0002, DK-0003, etc.)
3. **Fill in all sections:** Context, Decision Drivers, Options, Decision, Consequences, Validation
4. **Add interview tags:** Include 3-5 relevant topic tags (see taxonomy below)
5. **Update this README:** Add your ADR to the decision log table
6. **Include in feature branch:** Commit the ADR with your infrastructure changes

### Example

```bash
# During infrastructure work
git checkout -b infra/add-kubernetes

# Implement changes...

# Create ADR
cp docs/adr/TEMPLATE.md docs/adr/DK-0002-kubernetes-orchestration.md
# Fill in ADR content...

# Commit together
git add k8s/
git add docs/adr/DK-0002-kubernetes-orchestration.md
git add docs/adr/README.md  # Update decision log
git commit -m "Add Kubernetes orchestration

- Configure Kubernetes deployment manifests
- Document decision in DK-0002 ADR
- Update decision log"
```

## Interview Topic Tags

Tags help categorize decisions by interview topics. Use 3-5 tags per ADR:

- `#docker` - Containerization
- `#deployment` - Deployment strategies
- `#scalability` - System growth and performance
- `#developer-experience` - DX and workflow optimization
- `#ci-cd` - Continuous integration/deployment
- `#infrastructure` - Infrastructure choices
- `#monitoring` - Observability and logging
- `#security` - Security patterns
- `#database` - Database hosting and management
- `#networking` - Networking and load balancing
- `#testing` - Testing infrastructure

## Cross-References

- **Project Documentation:** See [CLAUDE.md](../../CLAUDE.md) for system architecture overview
- **Backend ADRs:** [maple_key_music_academy_backend/docs/adr/](../../maple_key_music_academy_backend/docs/adr/README.md)
- **Frontend ADRs:** [maple-key-music-academy-frontend/docs/adr/](../../maple-key-music-academy-frontend/docs/adr/README.md)

## Status Legend

- **Proposed:** Decision under review, not yet implemented
- **Accepted:** Final decision, implemented in the infrastructure
- **Deprecated:** No longer applicable or in use
- **Superseded:** Replaced by a newer ADR (link to replacement)
