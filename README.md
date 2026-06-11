# AHA Deployment

This repository contains the deployment configuration for the Obsidian + OAuth2 proxy application.

## Prerequisites

- Docker
- Docker Compose (v2) or docker-compose (v1)
- sudo access (if running on a server that requires elevated privileges for Docker)

## Environment Variables

Copy `.env.example` to `.env` and configure the required variables:

```bash
cp .env.example .env
```

Required environment variables:
- `PUID` - User ID for the container
- `PGID` - Group ID for the container
- `TZ` - Timezone
- `CONFIG_PATH` - Path to Obsidian configuration
- `SHM_SIZE` - Shared memory size
- `OBSIDIAN_IMAGE` - Obsidian Docker image
- `OBSIDIAN_CONTAINER_NAME` - Container name for Obsidian
- `HTTP_PORT` - HTTP port for the service
- `OAUTH2_PROVIDER` - OAuth2 provider
- `OAUTH2_CLIENT_ID` - OAuth2 client ID
- `OAUTH2_CLIENT_SECRET` - OAuth2 client secret
- `OAUTH2_OIDC_ISSUER_URL` - OIDC issuer URL
- `OAUTH2_REDIRECT_URL` - OAuth2 redirect URL
- `OAUTH2_COOKIE_SECRET` - Cookie secret for OAuth2
- `OAUTH2_EMAIL_DOMAIN` - Email domain for OAuth2

## Deployment

### Manual Deployment

Run the deployment script:

```bash
./deploy-ci.sh deploy
```

### TeamCity Deployment

The deployment is automated via TeamCity. The build configuration includes:

- **VCS Root**: `https://github.com/eunginx/AHA#refs/heads/main-dev`
- **Build Step**: Command Line script that runs `./deploy-ci.sh`
- **Environment Variable**: `USE_SUDO=true` (enabled for Docker commands)

When you push to the `main-dev` branch, TeamCity automatically triggers a deployment.

## Script Usage

The `deploy-ci.sh` script supports the following commands:

- `deploy` - Full deployment pipeline (default)
- `build` - Pull and build images
- `stop` - Stop containers and remove volumes/networks
- `start` - Start containers with rebuild
- `restart` - Restart containers
- `status` - Show container status
- `logs` - Show container logs
- `health` - Wait for services to be healthy
- `validate` - Validate docker-compose.yml

## Sudo Support

To enable sudo mode for Docker commands, set the `USE_SUDO` environment variable:

```bash
export USE_SUDO=true
./deploy-ci.sh deploy
```

This is automatically configured in the TeamCity build step.

## Services

- **Obsidian** - The main application running in a container with Wayland support
- **OAuth2 Proxy** - Authentication proxy for securing access to Obsidian

## Troubleshooting

Deployment logs are stored in `./deploy-logs/` directory. If a deployment fails, check the failure log for detailed diagnostics.

## Docker Compose

The application uses Docker Compose for orchestration. See `docker-compose.yml` for service definitions and configuration.
