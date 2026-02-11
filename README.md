# OpenCode GitHub/Gitea Repo Analyzer

A Dockerized solution that runs OpenCode to analyze GitHub **and Gitea** repositories and automatically creates AGENTS.md files via Pull Requests. Designed to run on K3s with external Ollama integration.

## Features

- **Multi-Architecture Support**: Works on both AMD64 and ARM64 (Raspberry Pi, Apple Silicon, AWS Graviton)
- **K3s Native**: Designed for Kubernetes CronJob scheduling
- **Automated PR Creation**: Creates branches and PRs with AGENTS.md files
- **Dual Git Provider Support**: Works with both **GitHub** and **Gitea** repositories
- **External Ollama**: Connects to your existing Ollama instance
- **Configurable Models**: Easy to switch between Ollama models
- **GitHub/Gitea Integration**: Uses GitHub CLI (gh) and Gitea CLI (tea) for PR creation
- **Persistent Output**: Logs and backups stored in PersistentVolume
- **Two Operating Modes**:
  - **AGENTS.md Mode**: One-time analysis generating documentation
  - **Autonomous Improvement Mode**: Continuous AI-driven code improvements with Git branching

## Operating Modes

### Mode 1: AGENTS.md Generation (Original)
Analyzes repositories and creates AGENTS.md files with coding guidelines.

**Use Case**: Initial setup, documentation generation

**Workflow**:
```
Clone repo → Analyze → Generate AGENTS.md → Create PR → Done
```

**Docker Image**: `ghcr.io/akolk/opencode-docker:latest`

### Mode 2: Autonomous Improvement (New)
AI continuously improves your codebase using Git branches and state tracking.

**Use Case**: Ongoing maintenance, refactoring, quality improvements

**Workflow**:
```
main branch ← develop branch ← OpenCode commits
                ↑
         .opencode/STATE.md
         (tracks progress)
```

**Features**:
- Works on `develop` branch (creates if missing)
- Maintains state in `.opencode/` directory
- Autonomously decides what to improve
- Auto-merges to `main` when tests pass
- Tracks all changes in `IMPROVEMENTS.md`

**Docker Image**: `ghcr.io/akolk/opencode-docker:autonomous-latest`

**Documentation**: See [docs/AUTONOMOUS_WORKFLOW.md](docs/AUTONOMOUS_WORKFLOW.md)

## Architecture

```
K3s CronJob (2x daily)
    ↓
Docker Container
    ├── Clone repo from GitHub
    ├── Run OpenCode analysis
    │   └── Connects to external Ollama
    ├── Generate AGENTS.md
    ├── Create branch & commit
    ├── Push to GitHub
    └── Create Pull Request
```

## Prerequisites

- Docker with buildx support (for multi-arch builds)
- Kubernetes cluster (K3s recommended)
- External Ollama instance accessible from cluster
- GitHub Personal Access Token with repo permissions

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/akolk/opencode-analyzer.git
cd opencode-analyzer
```

### 2. Configure Environment

Edit the following files:

#### `k8s/secret-github-token.yaml`
```yaml
stringData:
  GITHUB_TOKEN: "ghp_your_token_here"
```

#### `k8s/configmap-repos.yaml`
```yaml
data:
  repos.txt: |
    owner/repo1
    owner/repo2
    another-owner/another-repo
```

#### `k8s/cronjob.yaml`
Update the Ollama host:
```yaml
- name: OLLAMA_HOST
  value: "http://your-ollama-server:11434"
```

### 3. Get the Docker Image

**Option A: Use Pre-built Image (Recommended)**

The GitHub Actions workflow automatically builds and publishes images to the GitHub Container Registry:

**Package URL**: https://github.com/akolk/opencode-docker/pkgs/container/opencode-docker

```bash
# Pull the latest image
docker pull ghcr.io/akolk/opencode-docker:latest

# Or a specific version
docker pull ghcr.io/akolk/opencode-docker:v1.0.0
```

**Available Tags**:
- `latest` - Latest build from main branch
- `v1.0.0` - Specific version (replace with actual tag)
- `sha-xxxxxx` - Specific commit SHA

**⚠️ Important**: After the first workflow run, you need to make the package public:
1. Go to: https://github.com/akolk/opencode-docker/pkgs/container/opencode-docker
2. Click **"Package settings"**
3. Under **"Visibility"**, select **"Public"** (or keep Private if preferred)
4. Click **"Save"**

**Option B: Build Locally**

```bash
# Set up multi-arch builder (one time)
make setup-buildx

# Build and push to registry
make push REGISTRY=ghcr.io IMAGE_NAME=akolk/opencode-docker TAG=latest
```

### 4. Deploy to K3s

```bash
make k8s-deploy
```

### 5. Trigger Manual Run (Optional)

```bash
make k8s-run-now
```

## Automated CI/CD Builds

This repository includes **GitHub Actions** workflows that automatically build and push multi-arch Docker images:

### Build & Push Workflow

**File**: `.github/workflows/build-and-push.yml`

**Triggers**:
- Push to `main` branch
- Push version tags (`v*`)  
- Manual dispatch via GitHub UI
- Pull requests (build only, no push)

**Features**:
- ✅ Multi-platform builds: `linux/amd64`, `linux/arm64`
- ✅ Pushes to GitHub Container Registry (`ghcr.io`)
- ✅ Automatic tagging: branch names, semver, git SHA
- ✅ Layer caching for faster builds
- ✅ Test builds on PRs without pushing

### Using Pre-built Images

Instead of building locally, you can use the automated builds:

```bash
# Pull the latest image
docker pull ghcr.io/akolk/opencode-docker:latest

# Or a specific version
docker pull ghcr.io/akolk/opencode-docker:v1.0.0
```

Update your K8s deployment to use:
```yaml
image: ghcr.io/akolk/opencode-docker:latest
```

### Workflow Status

[![Build and Push](https://github.com/akolk/opencode-docker/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/akolk/opencode-docker/actions/workflows/build-and-push.yml)

View all runs: [Actions Tab](https://github.com/akolk/opencode-docker/actions)

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MODEL_PROVIDER` | AI provider: `ollama` or `kimi` | `ollama` |
| **Ollama Settings** | | |
| `OLLAMA_HOST` | Ollama server URL | `http://localhost:11434` |
| `OLLAMA_MODEL` | Ollama model name | `codellama:7b-code` |
| **Kimi Settings** | | |
| `KIMI_HOST` | Kimi-K2 endpoint URL | `http://localhost:1337` |
| `KIMI_MODEL` | Kimi model name | `kimi-k2.5` |
| `KIMI_API_KEY` | API key (if required) | `local` |
| **GitHub Settings** | | |
| `GITHUB_TOKEN` | GitHub PAT (required) | - |
| `GIT_AUTHOR_NAME` | Git commit author name | `OpenCode Bot` |
| `GIT_AUTHOR_EMAIL` | Git commit author email | `opencode-bot@example.com` |
| **Paths** | | |
| `REPOS_FILE` | Path to repo list | `/config/repos.txt` |
| `OUTPUT_DIR` | Output directory | `/output` |

### Changing Ollama Model

To use a different model (e.g., `llama3:8b`):

```bash
# In k8s/cronjob.yaml
- name: OLLAMA_MODEL
  value: "llama3:8b"
```

Then apply the change:
```bash
kubectl apply -f k8s/cronjob.yaml
```

### Model Provider Selection

OpenCode Analyzer supports multiple AI model providers. You can switch between **Ollama** (self-hosted) and **OpenCode Zen** (built-in free models).

#### Supported Providers

| Provider | Type | Configuration | Best For |
|----------|------|--------------|----------|
| **Ollama** | Self-hosted | Requires Ollama server | Full control, privacy, local development |
| **OpenCode Zen** | Built-in | Free models via OpenCode | Zero setup, free tier |

#### OpenCode Zen Free Models

OpenCode Zen provides access to free models:

| Model | Description | Best For |
|-------|-------------|----------|
| **kimi-k2.5-free** | Kimi K2.5 Free | General coding, analysis |
| **minimax-m2-free** | MiniMax M2 Free | Code generation, reasoning |

#### Switching to OpenCode Zen

To use OpenCode Zen instead of Ollama:

```yaml
# In k8s/cronjob.yaml or k8s/cronjob-autonomous.yaml

# Set the provider
- name: MODEL_PROVIDER
  value: "zen"

# Configure Zen (optional - uses defaults if not set)
- name: ZEN_HOST
  value: "https://opencode.ai/api/zen/v1"  # Or your hosted endpoint
  
- name: ZEN_MODEL
  value: "kimi-k2.5-free"  # Or "minimax-m2-free"

# Optional API key (if required by your Zen setup)
- name: ZEN_API_KEY
  value: "your-api-key"
```

Then apply:
```bash
kubectl apply -f k8s/cronjob.yaml
```

#### Environment Variables by Provider

**Ollama Mode** (`MODEL_PROVIDER=ollama`):
```yaml
- name: OLLAMA_HOST
  value: "http://ollama.your-domain.com:11434"
- name: OLLAMA_MODEL
  value: "codellama:7b-code"
  # Other options: "llama3:8b", "codellama:13b-code", "mistral:7b"
```

**Zen Mode** (`MODEL_PROVIDER=zen`):
```yaml
- name: ZEN_HOST
  value: "https://opencode.ai/api/zen/v1"  # Default Zen endpoint
- name: ZEN_MODEL
  value: "kimi-k2.5-free"  # Default free model
  # Other options: "minimax-m2-free"
- name: ZEN_API_KEY
  value: "local"  # Or your API key
```

#### Quick Provider Switch

**Option 1: Environment Variable**
```bash
# Deploy with Zen
kubectl set env cronjob/opencode-analyzer MODEL_PROVIDER=zen -n opencode-analyzer

# Switch back to Ollama
kubectl set env cronjob/opencode-analyzer MODEL_PROVIDER=ollama -n opencode-analyzer
```

**Option 2: Edit Config**
```bash
# Edit the cronjob
kubectl edit cronjob opencode-analyzer -n opencode-analyzer

# Change MODEL_PROVIDER value and save
```

#### Provider Comparison

| Feature | Ollama | OpenCode Zen |
|---------|--------|--------------|
| **Setup** | Requires Ollama server | Zero setup |
| **Privacy** | Fully private (local) | Uses OpenCode service |
| **Model Options** | Many (Llama, Mistral, etc.) | Free curated models |
| **Speed** | Depends on your hardware | Optimized cloud performance |
| **Cost** | Free (your hardware) | **Free tier available** |
| **Offline** | Yes | No (needs endpoint) |

## Makefile Commands

```bash
# Show all available commands
make help

# Build for local architecture
make build

# Build multi-arch image
make buildx

# Build and push to registry
make push TAG=v1.0.0

# Deploy to Kubernetes
make k8s-deploy

# Trigger manual run
make k8s-run-now

# View logs
make k8s-logs

# Check status
make k8s-status

# Remove from cluster
make k8s-delete
```

## Git Provider Support

OpenCode Analyzer supports both **GitHub** and **Gitea** repositories with automatic detection.

### Supported Git Providers

| Provider | Detection | Authentication | PR Creation |
|----------|-----------|----------------|-------------|
| **GitHub** | Auto-detected from URL | `GITHUB_TOKEN` | GitHub CLI (`gh`) |
| **Gitea** | Auto-detected from URL or explicit config | `GITEA_TOKEN` | Gitea CLI (`tea`) |

### Repository URL Formats

**GitHub** (default):
```text
# Simple format
owner/repo

# Full URL
https://github.com/owner/repo
```

**Gitea**:
```text
# With GITEA_HOST set to https://gitea.example.com:
owner/repo

# Full URL
https://gitea.example.com/owner/repo
```

### Git Provider Configuration

#### Option 1: Automatic Detection (Default)
```yaml
# Automatically detects provider from repo URL
- name: GIT_PROVIDER
  value: "auto"
```

#### Option 2: Explicit Provider Setting
```yaml
# Force GitHub (even for non-github.com URLs)
- name: GIT_PROVIDER
  value: "github"

# Force Gitea
- name: GIT_PROVIDER
  value: "gitea"
- name: GITEA_HOST
  value: "https://gitea.example.com"
```

### Setting Up Gitea Support

1. **Create Gitea Token Secret**:
```bash
# Edit k8s/secret-gitea-token.yaml
stringData:
  GITEA_TOKEN: "your-gitea-access-token"

# Apply the secret
kubectl apply -f k8s/secret-gitea-token.yaml
```

2. **Configure CronJob for Gitea**:
```yaml
# In k8s/cronjob.yaml or k8s/cronjob-autonomous.yaml
- name: GIT_PROVIDER
  value: "auto"  # or "gitea" for explicit

- name: GITEA_HOST
  value: "https://gitea.example.com"

- name: GITEA_TOKEN
  valueFrom:
    secretKeyRef:
      name: gitea-token
      key: GITEA_TOKEN
```

3. **Add Gitea Repositories**:
```yaml
# k8s/configmap-repos.yaml
data:
  repos.txt: |
    # GitHub repos (auto-detected)
    github.com/owner/repo1
    owner/repo2
    
    # Gitea repos (auto-detected via URL)
    https://gitea.example.com/owner/repo3
    
    # Or if GITEA_HOST is set:
    owner/repo4
```

### Mixed Git Providers

You can process both GitHub and Gitea repositories in the same run:

```yaml
data:
  repos.txt: |
    # These will use GitHub (auto-detected)
    facebook/react
    kubernetes/kubernetes
    
    # These will use Gitea (auto-detected via full URL)
    https://gitea.example.com/myorg/repo1
    https://gitea.example.com/myorg/repo2
```

### Provider Limitations

| Feature | GitHub | Gitea |
|---------|--------|-------|
| **Auto-merge** | ✅ Supported | ❌ Not available |
| **Issue checking** | ✅ Supported | ⚠️ Basic support |
| **PR creation** | ✅ Full support | ✅ Full support |
| **Private repos** | ✅ Supported | ✅ Supported |

## Repository List Format

The `repos.txt` file supports:

```text
# Comments are ignored
owner/repo-name

# Multiple repos
facebook/react
kubernetes/kubernetes
microsoft/vscode

# Blank lines are ignored

# Private repos work too (with proper token)
myorg/private-repo
```

## How It Works

1. **Scheduled Execution**: K3s CronJob triggers at 8 AM and 8 PM daily
2. **Repository Processing**: Container reads repo list and processes each one
3. **Analysis**: OpenCode analyzes codebase structure, build configs, and style patterns
4. **AGENTS.md Generation**: Creates comprehensive guidelines for coding agents
5. **Pull Request**: Creates branch `opencode/agents-md-{timestamp}` and opens PR
6. **Cleanup**: Removes cloned repository and continues to next one

## Generated AGENTS.md Structure

Each PR includes an `AGENTS.md` file with:

- **Build Commands**: How to build, test, and lint
- **Test Commands**: Especially running single tests
- **Code Style**: Import conventions, formatting, types
- **Naming Conventions**: Functions, variables, classes
- **Error Handling**: Patterns and best practices
- **Existing Rules**: Cursor rules or Copilot instructions

## Monitoring

### Check Job Status

```bash
# List CronJobs
kubectl get cronjobs -n opencode-analyzer

# List recent jobs
kubectl get jobs -n opencode-analyzer

# View logs
kubectl logs -n opencode-analyzer -l app=opencode-analyzer

# Check persistent volume
kubectl exec -n opencode-analyzer deploy/opencode-analyzer -- ls -la /output
```

### Output Files

The container stores:

- `/output/prs_created.csv` - List of all created PRs
- `/output/{repo}_AGENTS.md` - Backup of each generated file
- `/output/{repo}_analysis.log` - Detailed analysis logs

## Troubleshooting

### Pod Stuck Pending

```bash
# Check events
kubectl describe pod -n opencode-analyzer -l app=opencode-analyzer

# Common issues:
# - PVC not bound: Check storage class
# - Image pull error: Verify registry credentials
```

### Ollama Connection Failed

```bash
# Test connectivity from pod
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://your-ollama:11434/api/tags
```

### GitHub Authentication Failed

```bash
# Verify token
kubectl get secret github-token -n opencode-analyzer -o yaml
# Decode: echo 'BASE64_TOKEN' | base64 -d
```

## Multi-Architecture Support

The image supports:

- `linux/amd64` - Standard x86_64 servers
- `linux/arm64` - Raspberry Pi, Apple Silicon, AWS Graviton

To build for specific architecture:

```bash
# AMD64 only
docker buildx build --platform linux/amd64 -t myimage:latest .

# ARM64 only
docker buildx build --platform linux/arm64 -t myimage:latest .

# Both (default)
make push
```

## Development

### Local Testing

```bash
# Build locally
docker build -t opencode-analyzer:test .

# Run with test config
docker run -it --rm \
  -e GITHUB_TOKEN=ghp_xxx \
  -e OLLAMA_HOST=http://host.docker.internal:11434 \
  -v $(pwd)/test-repos.txt:/config/repos.txt \
  -v $(pwd)/output:/output \
  opencode-analyzer:test
```

### Customizing the Prompt

Edit `prompt.txt` to change what OpenCode analyzes:

```text
Please analyze this codebase and create an AGENTS.md file containing:
[Your custom requirements]
```

Then rebuild the image.

## Security Considerations

- GitHub token stored as Kubernetes Secret
- Container runs as non-root user
- Network policy recommended to restrict egress
- PersistentVolume can be encrypted at rest
- Ollama connection should use HTTPS in production

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a Pull Request

## License

MIT License - See LICENSE file for details

## Acknowledgments

- [OpenCode](https://opencode.ai) - The open source AI coding agent
- [Ollama](https://ollama.ai) - Local LLM runner
- [K3s](https://k3s.io) - Lightweight Kubernetes
