# OpenCode Autonomous Improvement Workflow

This document describes the AI-driven continuous improvement system using GitHub branches and state tracking.

## Architecture Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   main      │◄────│  develop    │◄────│  OpenCode   │
│  (stable)   │merge│   (work)    │push │   (AI bot)  │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │
       │            ┌──────┴──────┐
       │            │  .opencode/ │
       │            │  - STATE.md │
       │            │  - PLAN.md  │
       │            │  - IMPROV.  │
       │            └─────────────┘
       │
  ┌────┴────┐
  │ GitHub  │
  │ Actions │
  │(auto-   │
  │ merge)  │
  └─────────┘
```

## Branch Strategy

### `main` Branch
- **Purpose**: Production-ready, stable code
- **Protection**: Require tests to pass before merge
- **Updates**: Only via PR from `develop` branch
- **Triggers**: Auto-merge when tests pass

### `develop` Branch
- **Purpose**: AI workspace for improvements
- **Updates**: OpenCode commits directly
- **Contents**: Work-in-progress improvements
- **Sync**: Regularly synced with `main`

## Workflow Process

### 1. Initialization (First Run)

OpenCode will:
```bash
# Create develop branch from main
git checkout -b develop

# Create state tracking directory
mkdir -p .opencode/

# Initialize state files
cat > .opencode/STATE.md     # Current analysis
cat > .opencode/PLAN.md      # Roadmap
cat > .opencode/IMPROVEMENTS.md  # Completed work

# Commit and push
git add .opencode/
git commit -m "chore: Initialize OpenCode state tracking"
git push -u origin develop
```

### 2. Daily Operation

OpenCode runs via K3s CronJob:

```bash
1. Clone repository
2. Checkout develop branch (create if needed)
3. Read current state from .opencode/STATE.md
4. Analyze codebase autonomously
5. Determine next improvement (AI decision)
6. Implement improvement
7. Run tests
8. If tests pass:
   - Commit to develop
   - Update state files
   - Create PR to main
9. If tests fail:
   - Revert changes
   - Log failure in state
   - Alert for human review
```

### 3. Auto-Promotion

GitHub Actions handles promotion:

```yaml
# When PR from develop to main is created:
1. Run full test suite
2. If tests pass:
   - Auto-merge to main
   - Squash commits
   - Keep develop branch
3. If tests fail:
   - Block merge
   - Notify maintainers
```

## State Tracking

### STATE.md
Current context and analysis:
```markdown
# Current State

**Last Updated**: 2026-02-10
**Status**: Improving test coverage

## Current Focus
Working on increasing test coverage in src/utils/

## Recent Changes
- Refactored error handling module
- Added 15 new test cases

## Next Actions
1. Complete coverage for auth module
2. Document new error patterns

## Metrics
- Test Coverage: 67% → 72%
- Code Quality: A-
```

### IMPROVEMENTS.md
Log of completed work:
```markdown
### 2026-02-10 - Refactor Error Handling
- **Type**: refactoring
- **Scope**: src/utils/errors.js
- **Impact**: Reduced complexity by 40%
- **Commit**: abc123
- **PR**: #42
```

### PLAN.md
High-level roadmap:
```markdown
# Improvement Plan

## Short Term
- [ ] Increase test coverage to 80%
- [ ] Refactor authentication module
- [ ] Update dependencies

## Medium Term
- [ ] Performance optimization
- [ ] Security audit
```

## Human Integration

### Via GitHub Issues

Label issues for OpenCode:
- `opencode-priority` - Must address immediately
- `opencode-question` - Needs human input
- `opencode-bug` - Issue to fix

Example:
```markdown
Title: Refactor the database connection pooling
Labels: opencode-priority

The current implementation has connection leaks.
Please refactor to use connection pooling properly.
```

### Via Direct Commits

Humans can work on `develop` branch:
```bash
git checkout develop
# Make changes
git commit -m "feat: Human improvement"
git push origin develop
```

OpenCode will pull before working.

## Decision Matrix

OpenCode prioritizes improvements:

| Priority | Type | Example | Action |
|----------|------|---------|--------|
| P0 | Critical Bug | Security vulnerability | Fix immediately |
| P1 | High Impact | Performance bottleneck | Address next |
| P2 | Quality | Missing tests | Work on soon |
| P3 | Nice-to-have | Code style | Low priority |

## K3s Configuration

### CronJob Schedule

```yaml
# Run twice daily (8 AM, 8 PM)
schedule: "0 8,20 * * *"

# Or more frequently for active development
schedule: "0 */6 * * *"  # Every 6 hours
```

### Environment Variables

```yaml
- name: BRANCH_WORK
  value: "develop"
- name: BRANCH_MAIN
  value: "main"
- name: AUTO_MERGE
  value: "true"
- name: OLLAMA_MODEL
  value: "codellama:7b-code"
```

## Monitoring

### Check Status

```bash
# View state
kubectl exec -it deploy/opencode-analyzer -n opencode-analyzer -- \
  cat /workspace/repos/owner_repo_develop/.opencode/STATE.md

# View recent improvements
kubectl logs -n opencode-analyzer job/opencode-analyzer-xxxxx

# Check PRs created
gh pr list --repo owner/repo --author opencode-bot
```

### Metrics to Track

- Improvements per week
- Test coverage trend
- Failed attempts vs. successes
- Time from improvement to main

## Best Practices

### 1. Start Small
Begin with low-risk improvements to build trust:
- Documentation updates
- Code formatting
- Simple refactorings

### 2. Review Regularly
Even with auto-merge, periodically review:
- .opencode/IMPROVEMENTS.md
- Recent commits on develop
- Test coverage trends

### 3. Maintain Tests
Ensure test suite is:
- Comprehensive
- Fast (under 5 minutes)
- Reliable (not flaky)

### 4. Human Override
Always allow humans to:
- Pause OpenCode (delete CronJob)
- Revert changes (git revert)
- Direct priorities (GitHub issues)

### 5. Gradual Complexity
Start with:
- Week 1: Documentation only
- Week 2: Simple refactorings
- Week 3: Test additions
- Week 4: Feature improvements

## Troubleshooting

### Develop Branch Conflicts

If develop has diverged from main:
```bash
git checkout develop
git rebase main
git push --force-with-lease
```

### OpenCode Not Working

Check:
1. Ollama is accessible
2. GitHub token has repo access
3. develop branch exists
4. .opencode/ directory present

### Too Many PRs

Adjust frequency:
```yaml
# Reduce to daily
schedule: "0 9 * * *"

# Or batch by checking less frequently
```

### Human Changes Conflicts

Humans should:
1. Notify OpenCode (GitHub issue)
2. Work on feature branches
3. Merge to develop, not main

## Rollback

If an improvement causes issues:

```bash
# Revert specific commit on develop
git checkout develop
git revert <commit-hash>
git push

# Or reset develop to main
git checkout develop
git reset --hard main
git push --force
```

## Success Metrics

After 30 days, measure:
- [ ] Test coverage increased
- [ ] Code quality score improved
- [ ] Developer satisfaction high
- [ ] Manual work reduced
- [ ] No major incidents

## Future Enhancements

Potential improvements to this system:
- Multiple OpenCode instances (one per repo)
- A/B testing improvements
- ML-based prioritization
- Interactive approval for major changes
- Integration with code review tools
