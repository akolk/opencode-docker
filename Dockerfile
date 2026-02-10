# Multi-arch Dockerfile for OpenCode GitHub Repo Analyzer
# Supports linux/amd64 and linux/arm64

FROM node:20-slim

# Prevent interactive prompts during apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies: git, curl, ca-certificates, and gh CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (gh) for PR creation
# Multi-arch support: detect architecture and download appropriate binary
RUN ARCH=$(uname -m) && \
    case $ARCH in \
        x86_64) GH_ARCH="amd64" ;; \
        aarch64) GH_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/cli/cli/releases/download/v2.63.2/gh_2.63.2_linux_${GH_ARCH}.tar.gz" | \
    tar -xz -C /tmp && \
    cp /tmp/gh_2.63.2_linux_${GH_ARCH}/bin/gh /usr/local/bin/ && \
    rm -rf /tmp/gh_2.63.2_linux_*

# Create non-root user
RUN useradd -m -s /bin/bash opencode

# Install OpenCode CLI
RUN curl -fsSL https://opencode.ai/install | bash && \
    mv /root/.opencode /home/opencode/ && \
    chown -R opencode:opencode /home/opencode/.opencode

# Set environment variables
ENV PATH="/home/opencode/.opencode/bin:${PATH}"
ENV HOME=/home/opencode
ENV OLLAMA_HOST=${OLLAMA_HOST:-http://localhost:11434}
ENV OLLAMA_MODEL=${OLLAMA_MODEL:-codellama:7b-code}

# Switch to non-root user
USER opencode
WORKDIR /home/opencode

# Copy configuration files
COPY --chown=opencode:opencode opencode.json /home/opencode/.config/opencode/opencode.json
COPY --chown=opencode:opencode prompt.txt /home/opencode/prompt.txt
COPY --chown=opencode:opencode entrypoint.sh /home/opencode/entrypoint.sh

# Make entrypoint executable
RUN chmod +x /home/opencode/entrypoint.sh

# Create workspace directories
RUN mkdir -p /home/opencode/workspace/repos /home/opencode/workspace/output

# Set working directory to workspace
WORKDIR /home/opencode/workspace

# Entrypoint
ENTRYPOINT ["/home/opencode/entrypoint.sh"]
