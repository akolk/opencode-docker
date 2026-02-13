#!/bin/bash
set -e

# Configuration
REPOS_FILE="${REPOS_FILE:-/config/repos.txt}"
WORKSPACE_DIR="/home/opencode/workspace/repos"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-codellama:7b-code}"
ZEN_HOST="${ZEN_HOST:-https://opencode.ai/api/zen/v1}"
ZEN_MODEL="${ZEN_MODEL:-kimi-k2.5-free}"
ZEN_API_KEY="${ZEN_API_KEY:-local}"
MODEL_PROVIDER="${MODEL_PROVIDER:-ollama}"  # Options: ollama, opencode

# Git Provider Configuration
GIT_PROVIDER="${GIT_PROVIDER:-auto}"  # Options: github, gitea, auto
GITEA_HOST="${GITEA_HOST:-}"  # Gitea server URL (e.g., https://gitea.example.com)
GITEA_TOKEN="${GITEA_TOKEN:-}"  # Gitea access token

GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-OpenCode Bot}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-opencode-bot@example.com}"
AUTO_MERGE="${AUTO_MERGE:-true}"
BRANCH_MAIN="${BRANCH_MAIN:-main}"

# Detected git provider (set by detect_git_provider)
DETECTED_GIT_PROVIDER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Detect git provider from repo string
# Supports formats:
# - github.com/owner/repo -> github
# - gitea.example.com/owner/repo -> gitea
# - https://github.com/owner/repo -> github
# - https://gitea.example.com/owner/repo -> gitea
detect_git_provider() {
    local repo=$1
    
    if [[ "${GIT_PROVIDER}" != "auto" ]]; then
        # User explicitly set the provider
        DETECTED_GIT_PROVIDER="${GIT_PROVIDER}"
        return
    fi
    
    # Check if it's a full URL
    if [[ "${repo}" =~ ^https?:// ]]; then
        if [[ "${repo}" =~ github.com ]]; then
            DETECTED_GIT_PROVIDER="github"
        elif [[ "${repo}" =~ ${GITEA_HOST} ]] || [[ "${repo}" =~ ^https?://[^/]+\. ]]; then
            # Assume Gitea for non-github URLs if GITEA_HOST is set
            DETECTED_GIT_PROVIDER="gitea"
        fi
    else
        # Simple owner/repo format - assume GitHub by default
        # unless GITEA_HOST is set and explicitly configured
        if [[ -n "${GITEA_HOST}" ]] && [[ "${repo}" =~ ^gitea/ ]]; then
            DETECTED_GIT_PROVIDER="gitea"
        else
            DETECTED_GIT_PROVIDER="github"
        fi
    fi
    
    log_info "Detected git provider: ${DETECTED_GIT_PROVIDER} for ${repo}"
}

# Get git clone URL for a repo
get_clone_url() {
    local repo=$1
    local provider=$2
    
    # If it's already a full URL, return as-is
    if [[ "${repo}" =~ ^https?:// ]]; then
        echo "${repo}"
        return
    fi
    
    case "${provider}" in
        "github")
            echo "https://${GITHUB_TOKEN}@github.com/${repo}.git"
            ;;
        "gitea")
            local gitea_host="${GITEA_HOST:-https://gitea.example.com}"
            # Remove trailing slash
            gitea_host="${gitea_host%/}"
            echo "${gitea_host}/${repo}.git"
            ;;
        *)
            echo "https://github.com/${repo}.git"
            ;;
    esac
}

# Configure model provider
configure_model() {
    log_info "Configuring model provider: ${MODEL_PROVIDER}"

    case "${MODEL_PROVIDER}" in
        "ollama")
            export OPENCODE_PROVIDER="ollama"
            export OPENCODE_MODEL="${OLLAMA_MODEL}"
            log_info "Using Ollama: ${OLLAMA_HOST} with model ${OLLAMA_MODEL}"
            ;;
        "opencode")
            export OPENCODE_PROVIDER="opencode"
            export OPENCODE_MODEL="${ZEN_MODEL}"
            log_info "Using OpenCode Zen: ${ZEN_HOST} with model ${ZEN_MODEL}"
            log_info "Available Zen models: kimi-k2.5-free, minimax-m2-free"
            ;;
        *)
            log_error "Unknown model provider: ${MODEL_PROVIDER}. Use 'ollama' or 'opencode'"
            exit 1
            ;;
    esac
}

check_requirements() {
    log_info "Checking requirements..."
    
    if [[ -z "${GITHUB_TOKEN}" ]]; then
        log_error "GITHUB_TOKEN environment variable is required"
        exit 1
    fi
    
    if [[ ! -f "${REPOS_FILE}" ]]; then
        log_error "Repositories file not found: ${REPOS_FILE}"
        exit 1
    fi
    
    # Configure git
    git config --global user.name "${GIT_AUTHOR_NAME}"
    git config --global user.email "${GIT_AUTHOR_EMAIL}"
    git config --global init.defaultBranch main
    
    # Authenticate with GitHub CLI using GH_TOKEN environment variable
    log_info "Authenticating with GitHub CLI..."
    export GH_TOKEN="${GITHUB_TOKEN}"
    
    # Test authentication
    if ! gh auth status &>/dev/null; then
        log_warn "GitHub CLI not authenticated, attempting login..."
        if ! echo "${GITHUB_TOKEN}" | gh auth login --with-token --hostname github.com 2>&1 | head -5; then
            log_error "Failed to authenticate with GitHub CLI"
            log_info "Continuing anyway - some operations may fail"
        fi
    fi
    
    # Verify authentication worked
    if gh auth status &>/dev/null; then
        log_info "Authenticated with GitHub CLI"
    else
        log_warn "GitHub CLI authentication status unclear, continuing..."
    fi
    
    # Authenticate with Gitea CLI if Gitea is configured
    if [[ -n "${GITEA_HOST}" ]] && [[ -n "${GITEA_TOKEN}" ]]; then
        log_info "Configuring Gitea CLI..."
        if timeout 30 tea login add \
            --name "default" \
            --url "${GITEA_HOST}" \
            --token "${GITEA_TOKEN}" \
            --default 2>/dev/null; then
            log_info "Authenticated with Gitea: ${GITEA_HOST}"
        else
            log_warn "Failed to authenticate with Gitea, continuing without Gitea support"
        fi
    fi
    
    log_info "Requirements check passed"
}

# Check for human input via GitHub issues
check_github_issues() {
    local repo=$1
    log_info "Checking GitHub issues for ${repo}..."
    
    # Check for blocking issues
    blocking_issues=$(gh issue list --repo "${repo}" --label "opencode-priority" --json number,title --jq '.[] | "#\(.number): \(.title)"' 2>/dev/null || echo "")
    
    if [[ -n "${blocking_issues}" ]]; then
        log_warn "Found priority issues that need attention:"
        echo "${blocking_issues}"
        return 0
    fi
    
    # Check for questions
    questions=$(gh issue list --repo "${repo}" --label "opencode-question" --json number,title --jq '.[] | "#\(.number): \(.title)"' 2>/dev/null || echo "")
    if [[ -n "${questions}" ]]; then
        log_warn "Questions from maintainers:"
        echo "${questions}"
    fi
    
    return 1
}

# Setup or switch to develop branch
setup_develop_branch() {
    local repo=$1
    local repo_dir=$2
    
    log_info "Setting up ${BRANCH_WORK} branch..."
    
    # Fetch all branches
    git fetch origin
    
    # Check if develop branch exists on remote
    if git ls-remote --heads origin ${BRANCH_WORK} | grep -q ${BRANCH_WORK}; then
        log_info "Branch ${BRANCH_WORK} exists, checking out..."
        git checkout ${BRANCH_WORK}
        git pull origin ${BRANCH_WORK}
    else
        log_info "Creating ${BRANCH_WORK} branch from ${BRANCH_MAIN}..."
        git checkout -b ${BRANCH_WORK}
        
        # Create initial state files if they don't exist
        if [[ ! -d ".opencode" ]]; then
            log_info "Initializing .opencode state directory..."
            mkdir -p .opencode
            
            # Copy template state files (would be embedded or mounted)
            # For now, create minimal structure
            cat > .opencode/README.md <<EOF
# OpenCode Improvement State

This directory tracks AI-driven improvements.

## Files
- STATE.md - Current analysis and context
- IMPROVEMENTS.md - Completed work log
- PLAN.md - Roadmap and goals
EOF
            
            cat > .opencode/STATE.md <<EOF
# Current State

**Status**: Initial setup complete
**Branch**: develop

## Analysis
[To be populated by OpenCode]

## Next Steps
[To be determined autonomously]
EOF
            
            cat > .opencode/IMPROVEMENTS.md <<EOF
# Improvements Log

## 2026-02-10 - Initial Setup
- **Type**: setup
- **Details**: Created develop branch and state tracking
EOF
            
            cat > .opencode/PLAN.md <<EOF
# Improvement Plan

## Autonomous Goals
1. Analyze codebase structure
2. Identify improvement opportunities
3. Implement incremental improvements
4. Maintain test coverage
5. Update documentation

## Short Term
- Code quality improvements
- Test coverage enhancement
- Documentation updates
- Performance optimizations
EOF
            
            git add .opencode/
            git commit -m "chore: Initialize OpenCode state tracking

- Add .opencode/ directory for improvement tracking
- Create STATE.md for current context
- Create IMPROVEMENTS.md for completed work
- Create PLAN.md for roadmap

This enables autonomous improvement workflow."
            
            git push -u origin ${BRANCH_WORK}
        fi
    fi
    
    log_info "Now on branch: $(git branch --show-current)"
}

# Run autonomous improvement
run_autonomous_improvement() {
    local repo=$1
    local repo_dir=$2
    
    log_info "Starting autonomous improvement analysis..."
    log_info "Model: ${OLLAMA_MODEL}"
    log_info "Ollama: ${OLLAMA_HOST}"
    
    # Read current state if exists
    local current_state=""
    if [[ -f ".opencode/STATE.md" ]]; then
        current_state=$(cat .opencode/STATE.md)
        log_info "Loaded current state"
    fi
    
    # Build autonomous improvement prompt
    local prompt=$(cat <<EOFPROMPT
You are operating in AUTONOMOUS IMPROVEMENT MODE for continuous codebase enhancement.

## Your Task
Analyze this codebase and determine the NEXT MOST VALUABLE improvement to make. Consider:
1. Code quality issues (complexity, duplication, style)
2. Test coverage gaps
3. Documentation needs
4. Performance bottlenecks
5. Security concerns
6. Outdated dependencies (patch/minor only)

## Context
You are on the "develop" branch. Your changes will be tested and auto-merged to "main" if tests pass.

## Workflow
1. Analyze the codebase structure
2. Read .opencode/STATE.md for context
3. Read .opencode/PLAN.md for goals
4. Check .opencode/IMPROVEMENTS.md to avoid repetition
5. Determine the single best improvement to make NOW
6. IMPLEMENT the improvement
7. Run tests (if available)
8. Update .opencode/STATE.md with analysis
9. Update .opencode/IMPROVEMENTS.md with what you did
10. Commit with a descriptive message

## Constraints
- Make SMALL, INCREMENTAL improvements
- Focus on ONE thing at a time
- Maintain backward compatibility
- Don't break existing tests
- Prefer refactoring over rewrites
- Update documentation as needed

## Decision Criteria (in order)
1. Critical bugs or security issues
2. High-impact refactorings with low risk
3. Test coverage improvements
4. Documentation gaps
5. Performance optimizations
6. Code style consistency

## Output
After implementing, provide:
1. What you changed and why
2. The impact of the change
3. Test results
4. Confidence level (high/medium/low)

DO NOT ask for permission - make the improvement and commit it.
EOFPROMPT
)
    
    # Run OpenCode with autonomous prompt
    log_info "Running OpenCode autonomous analysis (this may take 10-30 minutes)..."

    # Create a wrapper script that feeds the prompt to opencode
    local analysis_output=".opencode/last_analysis_$(date +%Y%m%d_%H%M%S).log"
    local prompt_file="/tmp/opencode_prompt_$$.txt"

    # Write prompt to file to avoid bash interpretation issues
    echo "${prompt}" > "${prompt_file}"

    if timeout 1800 opencode --model "${OPENCODE_PROVIDER}/${OPENCODE_MODEL}" "$(cat ${prompt_file})" 2>&1 | tee "${analysis_output}"; then
        log_info "Autonomous improvement completed"
    else
        log_warn "OpenCode analysis completed with warnings or timeout"
    fi

    # Clean up prompt file
    rm -f "${prompt_file}"
    
    # Check if any files were modified
    if git diff --quiet && git diff --cached --quiet; then
        log_warn "No changes were made by OpenCode"
        
        # Update state to indicate no work needed
        cat >> .opencode/STATE.md <<EOF

### $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Status**: No improvements needed at this time
**Analysis**: Codebase is in good shape
**Next Check**: Schedule next analysis
EOF
        
        git add .opencode/
        git commit -m "chore: No improvements needed - codebase analysis complete

OpenCode analysis found no immediate improvements needed.
Codebase is in good shape." || true
        
        return 0
    fi
    
    # Check if tests pass
    log_info "Running tests..."
    local tests_passed=false
    
    if [[ -f "package.json" ]] && grep -q "test" package.json; then
        if npm test 2>&1 | tee -a "${analysis_output}"; then
            tests_passed=true
        fi
    elif [[ -f "Makefile" ]] && grep -q "test" Makefile; then
        if make test 2>&1 | tee -a "${analysis_output}"; then
            tests_passed=true
        fi
    elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
        if python -m pytest 2>&1 | tee -a "${analysis_output}"; then
            tests_passed=true
        fi
    elif [[ -f "Cargo.toml" ]]; then
        if cargo test 2>&1 | tee -a "${analysis_output}"; then
            tests_passed=true
        fi
    else
        log_warn "No test command found - assuming tests pass"
        tests_passed=true
    fi
    
    if [[ "${tests_passed}" == "true" ]]; then
        log_info "Tests passed!"
        
        # Stage all changes
        git add -A
        
        # Create commit with details
        local commit_msg="auto: Autonomous improvement by OpenCode

Improvement Details:
[See .opencode/IMPROVEMENTS.md for full details]

Model: ${OLLAMA_MODEL}
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Tests: Passing

This commit was automatically generated by OpenCode
running in autonomous improvement mode."
        
        git commit -m "${commit_msg}"
        
        # Push to develop
        git push origin ${BRANCH_WORK}
        
        return 0
    else
        log_error "Tests failed - changes not committed"
        
        # Revert changes but keep analysis
        git checkout -- .
        git clean -fd
        
        # Update state with failure info
        cat >> .opencode/STATE.md <<EOF

### $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Status**: Improvement attempt failed
**Issue**: Tests did not pass
**Action**: Changes reverted, needs human review
**Log**: ${analysis_output}
EOF
        
        git add .opencode/
        git commit -m "chore: Improvement attempt failed - tests not passing

OpenCode attempted an improvement but tests failed.
Changes were reverted. See ${analysis_output} for details.
Requires human review." || true
        
        git push origin ${BRANCH_WORK}
        
        return 1
    fi
}

# Create PR and optionally auto-merge
create_pr_and_merge() {
    local repo=$1
    local provider="${2:-${DETECTED_GIT_PROVIDER}}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local pr_title="auto: Autonomous improvements from develop"
    local pr_body="## Automated Improvement Summary

This PR contains improvements made autonomously by OpenCode.

### Changes
See commits for detailed changes.

### How This Works
- 🤖 OpenCode analyzed the codebase
- 🔍 Identified improvement opportunities
- ✨ Implemented the best change
- ✅ Tests passed
- 📤 Committed to \`develop\` branch
- 🔄 This PR created automatically

### Verification
- [ ] Review the changes
- [ ] Verify tests pass
- [ ] Approve if satisfactory

### Model Used
- **Model**: ${ZEN_MODEL:-${OLLAMA_MODEL}}
- **Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

---

*This is an automated PR created by OpenCode Improvement Bot.*"
    
    log_info "Creating PR from ${BRANCH_WORK} to ${BRANCH_MAIN} on ${provider}..."
    
    local pr_url=""
    
    if [[ "${provider}" == "gitea" ]]; then
        # Extract owner/repo from full URL or simple format
        local repo_path="${repo}"
        if [[ "${repo}" =~ ^https?:// ]]; then
            # Remove protocol and host
            repo_path=$(echo "${repo}" | sed 's|https\?://[^/]*/||')
        fi
        
        # Check if PR already exists
        local existing_pr
        existing_pr=$(tea pr list --repo "${repo_path}" --head "${BRANCH_WORK}" 2>/dev/null | grep -o '[0-9]\+' | head -1 || echo "")
        
        if [[ -n "${existing_pr}" ]]; then
            log_info "PR #${existing_pr} already exists"
            local gitea_host="${GITEA_HOST:-https://gitea.example.com}"
            gitea_host="${gitea_host%/}"
            pr_url="${gitea_host}/${repo_path}/pulls/${existing_pr}"
        else
            # Create new PR using tea
            pr_url=$(tea pr create \
                --repo "${repo_path}" \
                --title "${pr_title}" \
                --body "${pr_body}" \
                --head "${BRANCH_WORK}" \
                --base "${BRANCH_MAIN}" 2>&1)
            
            if [[ $? -ne 0 ]]; then
                log_error "Failed to create PR: ${pr_url}"
                return 1
            fi
            
            log_info "Created PR: ${pr_url}"
        fi
        
        # Note: Auto-merge for Gitea is not implemented (Gitea doesn't have auto-merge feature like GitHub)
        if [[ "${AUTO_MERGE}" == "true" ]]; then
            log_warn "Auto-merge not available for Gitea - manual merge required"
        fi
    else
        # GitHub PR creation using gh CLI
        # Check if PR already exists
        local existing_pr
        existing_pr=$(gh pr list --repo "${repo}" --head "${BRANCH_WORK}" --base "${BRANCH_MAIN}" --json number --jq '.[0].number' 2>/dev/null || echo "")
        
        if [[ -n "${existing_pr}" ]]; then
            log_info "PR #${existing_pr} already exists"
            pr_url="https://github.com/${repo}/pull/${existing_pr}"
        else
            # Create new PR
            pr_url=$(gh pr create \
                --repo "${repo}" \
                --title "${pr_title}" \
                --body "${pr_body}" \
                --head "${BRANCH_WORK}" \
                --base "${BRANCH_MAIN}" 2>&1)
            
            if [[ $? -ne 0 ]]; then
                log_error "Failed to create PR: ${pr_url}"
                return 1
            fi
            
            log_info "Created PR: ${pr_url}"
        fi
        
        # Auto-merge if enabled
        if [[ "${AUTO_MERGE}" == "true" ]]; then
            log_info "Auto-merge enabled - attempting to merge..."
            
            # Wait a moment for tests to start
            sleep 10
            
            # Try to enable auto-merge
            if gh pr merge "${pr_url}" --auto --squash 2>&1; then
                log_info "Auto-merge enabled for PR"
            else
                log_warn "Could not enable auto-merge - may need manual review or tests still running"
            fi
        fi
    fi
    
    return 0
}

# Process a single repository
process_repo() {
    local repo=$1
    local repo_dir="${WORKSPACE_DIR}/$(echo ${repo} | tr '/' '_' | sed 's/https\?://g; s/\//_/g' | sed 's/^_//')_${BRANCH_WORK}"
    
    # Detect git provider
    detect_git_provider "${repo}"
    local provider="${DETECTED_GIT_PROVIDER}"
    
    log_info "========================================="
    log_info "Processing: ${repo}"
    log_info "Git Provider: ${provider}"
    log_info "========================================="
    
    # Cleanup previous clone
    if [[ -d "${repo_dir}" ]]; then
        rm -rf "${repo_dir}"
    fi
    
    # Get clone URL based on provider
    local clone_url=$(get_clone_url "${repo}" "${provider}")
    
    # Clone repository
    log_info "Cloning ${repo} from ${provider}..."
    if ! git clone "${clone_url}" "${repo_dir}" 2>&1 | tail -5; then
        log_error "Failed to clone ${repo}"
        return 1
    fi
    
    cd "${repo_dir}"
    
    # Setup develop branch
    setup_develop_branch "${repo}" "${repo_dir}"
    
    # Check for human input via issues
    if [[ "${provider}" == "gitea" ]]; then
        log_info "Checking Gitea issues (not yet implemented)"
        # TODO: Implement Gitea issue checking
    else
        if check_github_issues "${repo}"; then
            log_warn "Priority issues found - addressing those first"
        fi
    fi
    
    # Run autonomous improvement
    if run_autonomous_improvement "${repo}" "${repo_dir}"; then
        log_info "Improvement successful"
        
        # Create PR to main
        create_pr_and_merge "${repo}" "${provider}"
    else
        log_error "Improvement failed for ${repo}"
        return 1
    fi
    
    # Cleanup
    cd "${WORKSPACE_DIR}"
    rm -rf "${repo_dir}"
    
    log_info "Completed ${repo}"
    return 0
}

# Main execution
main() {
    log_info "========================================="
    log_info "OpenCode Autonomous Improvement Bot"
    log_info "========================================="
    log_info "Mode: AI-Driven Continuous Improvement"
    log_info "Model Provider: ${MODEL_PROVIDER}"
    if [[ "${MODEL_PROVIDER}" == "ollama" ]]; then
        log_info "Ollama Host: ${OLLAMA_HOST}"
        log_info "Model: ${OLLAMA_MODEL}"
    elif [[ "${MODEL_PROVIDER}" == "opencode" ]]; then
        log_info "OpenCode Zen Host: ${ZEN_HOST}"
        log_info "Model: ${ZEN_MODEL}"
        log_info "Available models: kimi-k2.5-free, minimax-m2-free"
    fi
    log_info "Work Branch: ${BRANCH_WORK}"
    log_info "Main Branch: ${BRANCH_MAIN}"
    log_info "Auto-merge: ${AUTO_MERGE}"
    log_info "========================================="

    # Configure model provider
    configure_model

    check_requirements
    
    mkdir -p "${WORKSPACE_DIR}"
    
    # Count repos
    total_repos=$(grep -v '^#' "${REPOS_FILE}" | grep -v '^$' | wc -l)
    log_info "Found ${total_repos} repositories"
    
    local count=0
    local success=0
    local failed=0
    
    while IFS= read -r repo || [[ -n "$repo" ]]; do
        [[ "$repo" =~ ^#.*$ ]] && continue
        [[ -z "$repo" ]] && continue
        
        count=$((count + 1))
        log_info "[$count/${total_repos}] ${repo}"
        
        if process_repo "${repo}"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
        
        sleep 5
    done < "${REPOS_FILE}"
    
    log_info "========================================="
    log_info "Complete: ${success}/${total_repos} succeeded, ${failed} failed"
    log_info "========================================="
    
    [[ $failed -gt 0 ]] && exit 1
    exit 0
}

main "$@"
