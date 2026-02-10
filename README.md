# OpenCode GitHub Repo Analyzer

A Dockerized solution that runs OpenCode to analyze GitHub repositories and automatically creates AGENTS.md files via Pull Requests. Designed to run on K3s with external Ollama integration.

## Features

- **Multi-Architecture Support**: Works on both AMD64 and ARM64 (Raspberry Pi, Apple Silicon, AWS Graviton)
- **K3s Native**: Designed for Kubernetes CronJob scheduling
- **Automated PR Creation**: Creates branches and PRs with AGENTS.md files
- **External Ollama**: Connects to your existing Ollama instance
- **Configurable Models**: Easy to switch between Ollama models
- **GitHub Integration**: Uses GitHub CLI for PR creation
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
| `OLLAMA_HOST` | Ollama server URL | `http://localhost:11434` |
| `OLLAMA_MODEL` | Model to use | `codellama:7b-code` |
| `GITHUB_TOKEN` | GitHub PAT (required) | - |
| `GIT_AUTHOR_NAME` | Git commit author name | `OpenCode Bot` |
| `GIT_AUTHOR_EMAIL` | Git commit author email | `opencode-bot@example.com` |
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
