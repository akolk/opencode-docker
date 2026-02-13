# Completed Improvements

## 2026-02-10 - Fixed GitHub CLI Authentication

**Type**: bugfix  
**Scope**: entrypoint.sh, entrypoint-autonomous.sh  
**Impact**: Pod no longer hangs during startup

### Changes
- Export GH_TOKEN environment variable for gh CLI
- Add error handling and timeouts
- Don't exit on auth failure - continue with warning
- Better debugging output

### PR
Created via autonomous workflow

---

## 2026-02-10 - Added Gitea Support

**Type**: feature  
**Scope**: Dockerfiles, entrypoint scripts, K8s manifests  
**Impact**: Can now process both GitHub and Gitea repositories

### Changes
- Install tea CLI in Docker images
- Git provider auto-detection
- Separate authentication for GitHub and Gitea
- PR creation support for both providers

---

## 2026-02-10 - Added OpenCode Zen Provider

**Type**: feature  
**Scope**: opencode.json, entrypoint scripts  
**Impact**: Can use free models (kimi-k2.5-free, minimax-m2-free)

### Changes
- Support for zen provider alongside ollama
- Configuration via MODEL_PROVIDER env var
- Documentation for model switching

---

## 2026-02-10 - Fixed Multi-arch Docker Builds

**Type**: bugfix  
**Scope**: Dockerfile, Dockerfile.autonomous  
**Impact**: ARM64 builds now work correctly

### Changes
- Use TARGETARCH instead of uname -m
- Fix tea CLI download URL (gitea.com not github.com)
- Updated to tea v0.11.1

---

## 2026-02-10 - Fixed Bash Interpretation Error

**Type**: bugfix  
**Scope**: entrypoint-autonomous.sh  
**Impact**: Autonomous mode prompt no longer causes shell errors

### Changes
- Write prompt to temp file instead of inline bash -c
- Prevents special characters from being interpreted as commands
