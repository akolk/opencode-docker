#!/bin/bash
set -e

# Configuration
REPOS_FILE="${REPOS_FILE:-/config/repos.txt}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
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
WORKSPACE_DIR="/home/opencode/workspace/repos"
PROMPT_FILE="/home/opencode/prompt.txt"

# Detected git provider (set by detect_git_provider)
DETECTED_GIT_PROVIDER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

# Check required environment variables
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

# Create PR on GitHub using gh CLI
create_github_pr() {
    local repo=$1
    local branch_name=$2
    
    local pr_body="## Summary

This PR adds an \`AGENTS.md\` file to help agentic coding agents (like OpenCode, Claude Code, etc.) understand this codebase better.

## What's Included

- **Build Commands**: How to build, test, and lint the project
- **Test Commands**: Especially how to run a single test
- **Code Style**: Import conventions, formatting rules, types
- **Naming Conventions**: Functions, variables, classes, files
- **Error Handling**: Patterns and best practices
- **Existing Rules**: Any Cursor rules or Copilot instructions

## Generated By

- **Tool**: OpenCode
- **Model**: ${ZEN_MODEL:-${OLLAMA_MODEL}}
- **Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

---

*This is an automated PR. Please review the content and make adjustments as needed.*"
    
    local pr_url
    pr_url=$(gh pr create \
        --repo "${repo}" \
        --title "docs: Add AGENTS.md - Coding Agent Guidelines" \
        --body "${pr_body}" \
        --head "${branch_name}" \
        --base "main" 2>&1 || \
    gh pr create \
        --repo "${repo}" \
        --title "docs: Add AGENTS.md - Coding Agent Guidelines" \
        --body "## Summary

This PR adds an \`AGENTS.md\` file to help agentic coding agents understand this codebase." \
        --head "${branch_name}" \
        --base "master" 2>&1)
    
    echo "${pr_url}"
}

# Create PR on Gitea using tea CLI
create_gitea_pr() {
    local repo=$1
    local branch_name=$2
    
    # Extract owner/repo from full URL or simple format
    local repo_path="${repo}"
    if [[ "${repo}" =~ ^https?:// ]]; then
        # Remove protocol and host
        repo_path=$(echo "${repo}" | sed 's|https\?://[^/]*/||')
    fi
    
    local pr_body="This PR adds an AGENTS.md file to help agentic coding agents understand this codebase.

Generated by OpenCode with ${ZEN_MODEL:-${OLLAMA_MODEL}} on $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    
    local pr_url
    pr_url=$(tea pr create \
        --repo "${repo_path}" \
        --title "docs: Add AGENTS.md - Coding Agent Guidelines" \
        --body "${pr_body}" \
        --head "${branch_name}" \
        --base "main" 2>&1 || \
    tea pr create \
        --repo "${repo_path}" \
        --title "docs: Add AGENTS.md - Coding Agent Guidelines" \
        --body "${pr_body}" \
        --head "${branch_name}" \
        --base "master" 2>&1)
    
    echo "${pr_url}"
}

# Check if PR already exists for this repo
check_existing_pr() {
    local repo=$1
    local branch_name=$2
    local provider="${3:-${DETECTED_GIT_PROVIDER}}"
    
    log_info "Checking for existing PR in ${repo} (${provider})..."
    
    if [[ "${provider}" == "gitea" ]]; then
        # Extract owner/repo from full URL or simple format
        local repo_path="${repo}"
        if [[ "${repo}" =~ ^https?:// ]]; then
            # Remove protocol and host
            repo_path=$(echo "${repo}" | sed 's|https\?://[^/]*/||')
        fi
        
        # Check if branch exists on remote using tea
        if tea pr list --repo "${repo_path}" --head "${branch_name}" 2>/dev/null | grep -q "${branch_name}"; then
            log_warn "PR already exists for branch ${branch_name} in ${repo}"
            return 0
        fi
    else
        # Check if branch exists on remote using gh
        if gh api "repos/${repo}/git/ref/heads/${branch_name}" &>/dev/null; then
            # Check if PR exists for this branch
            existing_pr=$(gh pr list --repo "${repo}" --head "${branch_name}" --json number --jq '.[0].number' 2>/dev/null || echo "")
            if [[ -n "${existing_pr}" ]]; then
                log_warn "PR #${existing_pr} already exists for branch ${branch_name} in ${repo}"
                return 0
            fi
        fi
    fi
    
    return 1
}

# Process a single repository
process_repo() {
    local repo=$1
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local branch_name="opencode/agents-md-${timestamp}"
    local repo_dir="${WORKSPACE_DIR}/$(echo ${repo} | tr '/' '_' | sed 's/https\?://g; s/\//_/g' | sed 's/^_//')"
    
    # Detect git provider
    detect_git_provider "${repo}"
    local provider="${DETECTED_GIT_PROVIDER}"
    
    log_info "========================================="
    log_info "Processing repository: ${repo}"
    log_info "Git Provider: ${provider}"
    log_info "========================================="
    
    # Clean up previous clone if exists
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
    
    # Check if AGENTS.md already exists in PR
    if check_existing_pr "${repo}" "${branch_name}" "${provider}"; then
        log_warn "Skipping ${repo} - PR already exists"
        return 0
    fi
    
    # Check if AGENTS.md already exists in repo
    if [[ -f "AGENTS.md" ]]; then
        log_warn "AGENTS.md already exists in ${repo}"
        # Still continue to update it
    fi
    
    # Create and checkout new branch
    log_info "Creating branch: ${branch_name}"
    git checkout -b "${branch_name}"
    
    # Run OpenCode analysis
    log_info "Running OpenCode analysis with model: ${OLLAMA_MODEL}"
    log_info "Ollama host: ${OLLAMA_HOST}"
    
    # Read prompt
    local prompt=$(cat "${PROMPT_FILE}")
    
    # Run opencode with the prompt
    # Note: opencode runs in the repo directory and generates AGENTS.md
    log_info "Starting OpenCode analysis (this may take several minutes)..."
    
    # Create a temporary script for opencode to execute
    local temp_script=$(mktemp)
    cat > "${temp_script}" << 'EOFSCRIPT'
#!/bin/bash
# Read the prompt
PROMPT=$(cat /home/opencode/prompt.txt)
# Run opencode with the prompt
echo "${PROMPT}" | opencode --stdin
EOFSCRIPT
    chmod +x "${temp_script}"
    
    # Run opencode - it will analyze and may create files
    # We capture output but also let it work interactively if needed
    if timeout 1800 opencode --model "${OPENCODE_PROVIDER}/${OPENCODE_MODEL}" "${prompt}" 2>&1 | tee "${OUTPUT_DIR}/${repo//\//_}_analysis.log"; then
        log_info "OpenCode analysis completed"
    else
        log_warn "OpenCode analysis may have completed with warnings or timeout"
    fi
    
    # Check if AGENTS.md was created
    if [[ ! -f "AGENTS.md" ]]; then
        # Try to extract from output or create manually
        log_warn "AGENTS.md not created by OpenCode, attempting manual generation..."
        
        # Run opencode in a different way - interactive mode with explicit file creation
        timeout 600 bash -c "
            echo 'Please create an AGENTS.md file in the current directory with your analysis.

Run these commands in opencode:
1. Read the prompt at /home/opencode/prompt.txt
2. Analyze the codebase
3. Create AGENTS.md file with your findings
4. Exit' | opencode --stdin
        " 2>&1 | tee -a "${OUTPUT_DIR}/${repo//\//_}_analysis.log" || true
    fi
    
    # Final check for AGENTS.md
    if [[ ! -f "AGENTS.md" ]]; then
        log_error "AGENTS.md was not created for ${repo}"
        return 1
    fi
    
    # Copy AGENTS.md to output directory for backup
    cp "AGENTS.md" "${OUTPUT_DIR}/${repo//\//_}_AGENTS.md"
    
    # Commit and push changes
    log_info "Committing AGENTS.md..."
    git add AGENTS.md
    git commit -m "docs: Add AGENTS.md with codebase analysis

This file provides guidelines for agentic coding agents working in this repository:
- Build, test, and lint commands
- Code style guidelines
- Import conventions and naming patterns
- Error handling approaches

Generated by OpenCode with ${ZEN_MODEL:-${OLLAMA_MODEL}}"
    
    log_info "Pushing branch to ${provider}..."
    git push origin "${branch_name}"
    
    # Create Pull Request based on provider
    log_info "Creating Pull Request on ${provider}..."
    local pr_url=""
    
    if [[ "${provider}" == "gitea" ]]; then
        # Create PR using Gitea CLI (tea)
        pr_url=$(create_gitea_pr "${repo}" "${branch_name}")
    else
        # Create PR using GitHub CLI (gh)
        pr_url=$(create_github_pr "${repo}" "${branch_name}")
    fi
    
    if [[ $? -eq 0 ]] && [[ -n "${pr_url}" ]]; then
        log_info "PR created successfully: ${pr_url}"
        echo "${repo},${pr_url},$(date -u +"%Y-%m-%d %H:%M:%S")" >> "${OUTPUT_DIR}/prs_created.csv"
    else
        log_error "Failed to create PR for ${repo}"
        return 1
    fi
    
    # Cleanup
    cd "${WORKSPACE_DIR}"
    rm -rf "${repo_dir}"
    
    log_info "Completed processing ${repo}"
    return 0
}

# Main execution
main() {
    log_info "========================================="
    log_info "OpenCode GitHub Repo Analyzer"
    log_info "========================================="
    log_info "Model Provider: ${MODEL_PROVIDER}"
    if [[ "${MODEL_PROVIDER}" == "ollama" ]]; then
        log_info "Ollama Host: ${OLLAMA_HOST}"
        log_info "Model: ${OLLAMA_MODEL}"
    elif [[ "${MODEL_PROVIDER}" == "opencode" ]]; then
        log_info "OpenCode Zen Host: ${ZEN_HOST}"
        log_info "Model: ${ZEN_MODEL}"
        log_info "Available models: kimi-k2.5-free, minimax-m2-free"
    fi
    log_info "Repositories file: ${REPOS_FILE}"
    log_info "Output directory: ${OUTPUT_DIR}"
    log_info "========================================="
    
    # Configure model provider
    configure_model
    
    # Check requirements
    check_requirements
    
    # Create output directory
    mkdir -p "${OUTPUT_DIR}"
    
    # Initialize PR tracking file
    echo "repo,pr_url,timestamp" > "${OUTPUT_DIR}/prs_created.csv"
    
    # Count total repos
    total_repos=$(grep -v '^#' "${REPOS_FILE}" | grep -v '^$' | wc -l)
    log_info "Found ${total_repos} repositories to process"
    
    # Process each repository
    local count=0
    local success=0
    local failed=0
    
    while IFS= read -r repo || [[ -n "$repo" ]]; do
        # Skip comments and empty lines
        [[ "$repo" =~ ^#.*$ ]] && continue
        [[ -z "$repo" ]] && continue
        
        count=$((count + 1))
        log_info "[$count/${total_repos}] Processing: ${repo}"
        
        if process_repo "${repo}"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
            log_error "Failed to process ${repo}"
        fi
        
        # Small delay between repos to avoid rate limits
        sleep 5
        
    done < "${REPOS_FILE}"
    
    # Summary
    log_info "========================================="
    log_info "Processing Complete"
    log_info "========================================="
    log_info "Total: ${total_repos}"
    log_info "Success: ${success}"
    log_info "Failed: ${failed}"
    log_info "Output directory: ${OUTPUT_DIR}"
    log_info "PR tracking: ${OUTPUT_DIR}/prs_created.csv"
    
    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
    
    exit 0
}

# Run main
main "$@"
