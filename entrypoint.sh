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
MODEL_PROVIDER="${MODEL_PROVIDER:-ollama}"  # Options: ollama, zen
GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-OpenCode Bot}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-opencode-bot@example.com}"
WORKSPACE_DIR="/home/opencode/workspace/repos"
PROMPT_FILE="/home/opencode/prompt.txt"

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
        "zen")
            export OPENCODE_PROVIDER="zen"
            export OPENCODE_MODEL="${ZEN_MODEL}"
            log_info "Using OpenCode Zen: ${ZEN_HOST} with model ${ZEN_MODEL}"
            log_info "Available Zen models: kimi-k2.5-free, minimax-m2-free"
            ;;
        *)
            log_error "Unknown model provider: ${MODEL_PROVIDER}. Use 'ollama' or 'zen'"
            exit 1
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
    
    # Authenticate with GitHub CLI
    echo "${GITHUB_TOKEN}" | gh auth login --with-token
    
    log_info "Requirements check passed"
}

# Check if PR already exists for this repo
check_existing_pr() {
    local repo=$1
    local branch_name=$2
    
    log_info "Checking for existing PR in ${repo}..."
    
    # Check if branch exists on remote
    if gh api "repos/${repo}/git/ref/heads/${branch_name}" &>/dev/null; then
        # Check if PR exists for this branch
        existing_pr=$(gh pr list --repo "${repo}" --head "${branch_name}" --json number --jq '.[0].number' 2>/dev/null || echo "")
        if [[ -n "${existing_pr}" ]]; then
            log_warn "PR #${existing_pr} already exists for branch ${branch_name} in ${repo}"
            return 0
        fi
    fi
    
    return 1
}

# Process a single repository
process_repo() {
    local repo=$1
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local branch_name="opencode/agents-md-${timestamp}"
    local repo_dir="${WORKSPACE_DIR}/$(echo ${repo} | tr '/' '_')"
    
    log_info "========================================="
    log_info "Processing repository: ${repo}"
    log_info "========================================="
    
    # Clean up previous clone if exists
    if [[ -d "${repo_dir}" ]]; then
        rm -rf "${repo_dir}"
    fi
    
    # Clone repository
    log_info "Cloning ${repo}..."
    if ! git clone "https://${GITHUB_TOKEN}@github.com/${repo}.git" "${repo_dir}" 2>&1 | tail -5; then
        log_error "Failed to clone ${repo}"
        return 1
    fi
    
    cd "${repo_dir}"
    
    # Check if AGENTS.md already exists in PR
    if check_existing_pr "${repo}" "${branch_name}"; then
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
    if timeout 1800 opencode --task "${prompt}" 2>&1 | tee "${OUTPUT_DIR}/${repo//\//_}_analysis.log"; then
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

Generated by OpenCode with ${OLLAMA_MODEL}"
    
    log_info "Pushing branch to GitHub..."
    git push origin "${branch_name}"
    
    # Create Pull Request
    log_info "Creating Pull Request..."
    pr_url=$(gh pr create \
        --repo "${repo}" \
        --title "docs: Add AGENTS.md - Coding Agent Guidelines" \
        --body "## Summary

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
- **Model**: ${OLLAMA_MODEL}
- **Timestamp**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- **Ollama Host**: ${OLLAMA_HOST}

---

*This is an automated PR. Please review the content and make adjustments as needed.*" \
        --head "${branch_name}" \
        --base "main" 2>&1 || \
    gh pr create \
        --repo "${repo}" \
        --title "docs: Add AGENTS.md - Coding Agent Guidelines" \
        --body "## Summary

This PR adds an \`AGENTS.md\` file to help agentic coding agents understand this codebase." \
        --head "${branch_name}" \
        --base "master" 2>&1)
    
    if [[ $? -eq 0 ]]; then
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
    elif [[ "${MODEL_PROVIDER}" == "zen" ]]; then
        log_info "Zen Host: ${ZEN_HOST}"
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
