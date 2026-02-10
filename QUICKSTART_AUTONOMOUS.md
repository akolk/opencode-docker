# 🚀 Quick Start: Autonomous Improvement Workflow

## What You Just Got

A complete AI-driven continuous improvement system that:
1. Uses **Git branches** (main + develop) for safe experimentation
2. Tracks **state** in markdown files
3. **Autonomously decides** what to improve next
4. **Auto-merges** to main when tests pass

## Architecture

```
Your Repository
├── main (stable, production)
│   └── protected branch
│
├── develop (AI workspace)
│   └── OpenCode commits here
│   └── .opencode/
│       ├── STATE.md (current focus)
│       ├── IMPROVEMENTS.md (what's done)
│       └── PLAN.md (roadmap)
│
└── Pull Requests
    └── develop → main
        └── Auto-merges if tests pass
```

## Step-by-Step Setup

### 1. Prepare Target Repositories

For each repository you want to improve, add these files:

**Option A: Copy from template-repo/**
```bash
cd your-target-repo
cp -r /path/to/opencode-docker/template-repo/.opencode/ .
cp -r /path/to/opencode-docker/template-repo/.github/workflows/ .
git add .
git commit -m "chore: Setup OpenCode autonomous improvement"
git push
```

**Option B: Manual Setup**

Create `.github/workflows/test.yml`:
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: npm test  # or your test command
```

Create `.github/workflows/auto-merge.yml`:
```yaml
name: Auto-Merge
on:
  pull_request:
    branches: [main]
jobs:
  auto-merge:
    runs-on: ubuntu-latest
    if: github.head_ref == 'develop'
    steps:
      - name: Auto-merge
        uses: pascalgn/automerge-action@v0.16.2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 2. Configure OpenCode Analyzer

Edit `k8s/cronjob-autonomous.yaml`:

```yaml
- name: OLLAMA_HOST
  value: "http://your-ollama-server:11434"

- name: OLLAMA_MODEL
  value: "codellama:7b-code"  # or "llama3:8b", etc.
```

### 3. Add Your Repositories

Edit `k8s/configmap-repos.yaml`:

```yaml
data:
  repos.txt: |
    your-org/repo1
    your-org/repo2
    another-org/another-repo
```

### 4. Deploy to K3s

```bash
# Deploy autonomous mode
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap-repos.yaml
kubectl apply -f k8s/secret-github-token.yaml
kubectl apply -f k8s/cronjob-autonomous.yaml

# Trigger first run manually
kubectl create job --from=cronjob/opencode-autonomous manual-run -n opencode-analyzer
```

### 5. Watch It Work

```bash
# View logs
kubectl logs -n opencode-analyzer -l job-name=manual-run -f

# Check GitHub
# You'll see:
# 1. New "develop" branch created
# 2. .opencode/ directory added
# 3. First improvement committed
# 4. PR created: develop → main
# 5. Auto-merged (if tests pass)
```

## How It Works

### Day 1: Initialization
1. OpenCode clones your repo
2. Creates `develop` branch
3. Adds `.opencode/` directory with state files
4. Pushes to GitHub
5. Creates first improvement PR

### Day 2+: Continuous Improvement
1. OpenCode checks out `develop`
2. Reads `STATE.md` for context
3. Analyzes codebase
4. Decides what to improve (autonomous)
5. Implements change
6. Runs tests
7. If tests pass → commits & pushes
8. Creates PR to `main`
9. GitHub Actions auto-merges
10. Updates state files

## Human Control

### Via GitHub Issues

Create issues with these labels:
- `opencode-priority` - Do this next
- `opencode-question` - Needs your input
- `opencode-bug` - Fix this issue

Example:
```markdown
Title: Refactor database queries
Labels: opencode-priority

The current N+1 queries are slow. 
Please refactor to use joins.
```

### Via Direct Commits

```bash
git checkout develop
# Make your changes
git commit -m "feat: Human improvement"
git push
```

### Pause/Resume

```bash
# Pause
kubectl delete cronjob opencode-autonomous -n opencode-analyzer

# Resume
kubectl apply -f k8s/cronjob-autonomous.yaml
```

## State Files

### STATE.md - Current Context
```markdown
# Current State

**Last Updated**: 2026-02-10
**Status**: Improving error handling

## Recent Changes
- Refactored auth module
- Added 5 new test cases

## Next Actions
1. Complete error handling refactor
2. Update documentation

## Metrics
- Test Coverage: 72%
```

### IMPROVEMENTS.md - Completed Work
```markdown
### 2026-02-10 - Refactor Auth Module
- **Type**: refactoring
- **Scope**: src/auth/
- **Impact**: Reduced complexity by 30%
- **Commit**: abc123
- **PR**: #15
```

### PLAN.md - Roadmap
```markdown
# Improvement Plan

## Short Term
- [ ] Increase test coverage to 80%
- [ ] Refactor error handling
- [ ] Update dependencies

## Medium Term
- [ ] Performance optimization
```

## Customization

### Change Improvement Frequency

```yaml
# k8s/cronjob-autonomous.yaml

# Every 6 hours (more aggressive)
schedule: "0 */6 * * *"

# Daily at 9 AM
schedule: "0 9 * * *"

# Twice daily (default)
schedule: "0 8,20 * * *"
```

### Change Ollama Model

```yaml
# Faster, smaller model
- name: OLLAMA_MODEL
  value: "codellama:7b-code"

# More capable model
- name: OLLAMA_MODEL
  value: "llama3:8b"

# Code-specific model
- name: OLLAMA_MODEL
  value: "deepseek-coder:6.7b"
```

### Disable Auto-Merge

```yaml
- name: AUTO_MERGE
  value: "false"
```

Then manually review PRs before merging.

## Monitoring

### View Current Activity

```bash
# Check what OpenCode is doing
kubectl logs -n opencode-analyzer -l app=opencode-analyzer -f

# View state of a specific repo
kubectl exec -it deploy/opencode-analyzer -n opencode-analyzer -- \
  cat /workspace/repos/your-org_your-repo_develop/.opencode/STATE.md
```

### Track Improvements

```bash
# List all PRs created by OpenCode
gh pr list --repo your-org/your-repo --author opencode-bot --state all

# View improvement log
cat .opencode/IMPROVEMENTS.md
```

## Troubleshooting

### No improvements happening
Check:
1. Ollama is running and accessible
2. GitHub token has repo permissions
3. Look at logs: `kubectl logs ...`

### Tests failing
OpenCode will:
- Revert changes
- Log failure in STATE.md
- Try different approach next time

### Too many PRs
Reduce frequency in CronJob schedule.

### Want to rollback
```bash
git checkout develop
git revert <bad-commit>
git push
```

## Best Practices

1. **Start with 1-2 repos** to test
2. **Ensure good test coverage** before starting
3. **Review first few PRs** manually
4. **Check STATE.md regularly** to understand progress
5. **Use GitHub issues** for direction when needed

## Next Steps

1. ✅ Setup complete - files pushed to GitHub
2. ⏳ Wait for GitHub Actions to build images
3. 🚀 Deploy to your K3s cluster
4. 👀 Monitor first run
5. 🎉 Watch your code improve itself!

## Documentation

- Full details: [docs/AUTONOMOUS_WORKFLOW.md](docs/AUTONOMOUS_WORKFLOW.md)
- Original AGENTS.md mode: See main README.md

---

**Happy automated improving!** 🤖✨
