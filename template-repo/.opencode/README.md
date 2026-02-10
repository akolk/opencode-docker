# OpenCode Improvement State

This directory tracks the AI-driven improvement workflow for this repository.

## Files

- **STATE.md** - Current analysis context and recent changes
- **IMPROVEMENTS.md** - Log of all completed improvements
- **PLAN.md** - High-level roadmap and goals
- **metrics/** - Performance and quality metrics over time

## How It Works

1. OpenCode runs on `develop` branch
2. Analyzes current codebase state
3. Checks GitHub issues for human input
4. Determines next improvement (autonomous)
5. Implements and tests
6. Updates these state files
7. Commits to develop
8. Creates PR to main (auto-merges on success)

## Human Input

Create GitHub issues with labels:
- `opencode-priority` - Must do next
- `opencode-question` - Needs human decision
- `opencode-bug` - Issue found by AI
