# Dockerfile for obsidian-private
# Builds a custom image based on the running linuxserver/obsidian solution
FROM linuxserver/obsidian:1.12.7

LABEL maintainer="your-email@example.com"
LABEL description="Private Obsidian image with custom configuration"

# Add any custom packages or config layers here if needed
# e.g. COPY custom-config /config

EXPOSE 3000 3001
