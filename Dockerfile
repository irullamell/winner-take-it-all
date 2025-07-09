# Dockerfile: all‑in‑one Jekyll + code‑server environment
FROM ruby:3.3-slim

LABEL maintainer="you@example.com"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CODE_SERVER_VERSION=4.24.1

# ---- dependencies & Jekyll ----
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        curl \
        ca-certificates \
        libssl-dev \
    && gem install --no-document jekyll bundler \
    # ---- code‑server ----
    && curl -fL https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb -o /tmp/code-server.deb \
    && apt-get install -y /tmp/code-server.deb \
    && rm /tmp/code-server.deb \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- non‑root user ----
RUN useradd -ms /bin/bash dev
USER dev
WORKDIR /home/dev/site

# ---- ports ----
EXPOSE 4000 8080

# ---- entrypoint : init site (once) & launch both services ----
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["[ \"$(ls -A)\" ] || jekyll new . --force && (jekyll serve --livereload --host 0.0.0.0 --port 4000 &) && code-server --bind-addr 0.0.0.0:8080 --auth none"]
