# AHA Deployment

This repository contains the deployment configuration for the Obsidian application with OAuth2 authentication proxy, designed to run on headless EC2 instances.

## Architecture

The application consists of three main services:

- **Xvfb** - X Virtual Frame Buffer providing a virtual display server (1920x1080x24) for headless environments
- **Obsidian** - Main application container using the virtual display via X11
- **OAuth2 Proxy** - Authentication proxy securing access to Obsidian via OIDC

**Request Flow:**
```
User → Nginx Proxy Manager → OAuth2 Proxy (port 4180) → Obsidian (port 3000)
```

## Prerequisites

- Docker
- Docker Compose (v2) or docker-compose (v1)
- sudo access (if running on a server that requires elevated privileges for Docker)
- Nginx Proxy Manager (for reverse proxy configuration)
- OIDC provider (e.g., Authentik)

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
- `SHM_SIZE` - Shared memory size (default: 1gb)
- `OBSIDIAN_IMAGE` - Obsidian Docker image (default: linuxserver/obsidian:1.12.7)
- `OBSIDIAN_CONTAINER_NAME` - Container name for Obsidian
- `HTTP_PORT` - HTTP port for the service (default: 3000)
- `HTTPS_PORT` - HTTPS port for the service (default: 3002)
- `OAUTH2_ENABLED` - Enable OAuth2 proxy (default: true)
- `OAUTH2_PROVIDER` - OAuth2 provider (default: oidc)
- `OAUTH2_CLIENT_ID` - OAuth2 client ID
- `OAUTH2_CLIENT_SECRET` - OAuth2 client secret
- `OAUTH2_OIDC_ISSUER_URL` - OIDC issuer URL
- `OAUTH2_REDIRECT_URL` - OAuth2 redirect URL
- `OAUTH2_COOKIE_SECRET` - Cookie secret for OAuth2 (must be 16, 24, or 32 characters)
- `OAUTH2_EMAIL_DOMAIN` - Email domain for OAuth2 (comma-separated)
- `OAUTH2_PROXY_COOKIE_SECURE` - Cookie secure flag (default: true for HTTPS)

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

### Xvfb
- **Image**: alpine:latest
- **Purpose**: Provides virtual display server for headless environments
- **Display**: :0 (1920x1080x24 with GLX and render extensions)
- **Network**: obsidian-net

### Obsidian
- **Image**: linuxserver/obsidian:1.12.7
- **Purpose**: Main application container
- **Display**: Uses Xvfb virtual display (DISPLAY=:0)
- **Mode**: X11 (PIXELFLUX_WAYLAND=false)
- **Selkies**: Websockets mode for remote access
- **Network**: obsidian-net
- **Dependencies**: Requires Xvfb service to start first

### OAuth2 Proxy
- **Image**: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
- **Purpose**: Authentication proxy for securing access to Obsidian
- **Provider**: OIDC
- **Upstream**: http://obsidian:3000
- **Port**: 4180
- **Websocket Support**: Enabled (required for Selkies)
- **Network**: obsidian-net
- **Dependencies**: Requires Obsidian to be healthy

## Nginx Proxy Manager Configuration

Configure Nginx Proxy Manager with the following settings:

- **Domain**: Your domain (e.g., aha.sorsiri.in)
- **Scheme**: HTTPS
- **Forward Hostname**: Host IP address
- **Forward Port**: 4180 (OAuth2 Proxy)
- **SSL Certificate**: Let's Encrypt
- **WebSocket Support**: Enabled
- **Access Control**: OAuth2 Proxy handles authentication

## Troubleshooting

### Container Startup Issues
If containers are created but not starting:
- Check if `docker compose up` is working correctly
- The script includes automatic fallback to `docker compose start`
- Check Docker logs: `docker logs obsidian` or `docker logs oauth2-proxy`

### Port Conflicts
If you encounter port allocation errors:
- Check which ports are in use: `docker ps` and `netstat -tulpn`
- Update `HTTP_PORT` and `HTTPS_PORT` in `.env` file
- Common conflict: Port 3001 used by pydllm-ui-1 container

### Blank Screen Issue
If the screen is blank after authentication:
- Verify Xvfb is running: `docker logs xvfb`
- Check obsidian display configuration: `docker exec obsidian env | grep DISPLAY`
- Ensure obsidian is using X11 (PIXELFLUX_WAYLAND=false) not Wayland

### Network Issues
If OAuth2 proxy cannot reach obsidian:
- Verify both containers are on the same network: `docker network inspect obsidian-net`
- Check container network connections: `docker inspect obsidian | grep -A 10 Networks`
- Verify DNS resolution: `docker exec oauth2-proxy ping obsidian`

### Permission Issues
If you encounter Docker permission errors:
- Set `USE_SUDO=true` in TeamCity environment variables
- Or add user to docker group: `sudo usermod -aG docker $USER`

Deployment logs are stored in `./deploy-logs/` directory. If a deployment fails, check the failure log for detailed diagnostics.

## Docker Compose

The application uses Docker Compose for orchestration. See `docker-compose.yml` for service definitions and configuration.

## Version History

### v1.0.0 (Current)
- Initial stable release
- Xvfb virtual display support for headless EC2
- OAuth2 proxy with OIDC authentication
- Nginx Proxy Manager integration
- Automated TeamCity deployment
- Comprehensive debug logging
- Port conflict resolution
- Container startup fallback mechanisms
