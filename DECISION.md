# Project Explainer and thought process

Hehe, deadline change.

Click on this commit [link](https://github.com/Muturi-002/NGINX-Docker-Compose/commit/751cd659126962f286b1348c3ac8ef126f3a7909) to find the original changes.

## Project Explainer
The objective of this project was to implement a Blue-Green deployment strategy for Node.js behind NGINX using pre-built container images. The setup provides automatic failover, health-based routing, and zero-downtime deployments. The containers for the Blue-Green deployment were already provided, customized for this project.

### Architecture
#### What's Being Deployed
- **Two identical Node.js services** shipped as ready-to-run images:
  - **Blue** (active) instance
  - **Green** (backup) instance
- **NGINX** as a reverse proxy with intelligent failover

#### Available Endpoints
Each service exposes these endpoints (already implemented in the image):
- `GET /version` → Returns JSON and headers
- `POST /chaos/start` → Simulates downtime (500s or timeout)
- `POST /chaos/stop` → Ends simulated downtime
- `GET /healthz` → Process liveness check

#### NGINX Configuration Requirements
- **Normal state**: All traffic routes to Blue
- **On Blue failure**: NGINX automatically switches to Green with zero failed client requests
- **Retry logic**: If Blue fails (timeout or 5xx), NGINX retries to Green within the same client request
- **Default behavior**: Blue is active, Green is backup
- **Header forwarding**: All upstream headers are preserved and forwarded to clients

#### Failover Mechanics
- Primary/backup upstream configuration
- Tight timeouts for quick failure detection
- Retry policy for error, timeout, and http_5xx conditions
- Low `max_fails` + short `fail_timeout` for primary

***Environment Configuration***

#### Port Mapping
- **NGINX public entrypoint**: `http://localhost:8080`
- **Blue direct port**: `http://localhost:8081` (for chaos testing)
- **Green direct port**: `http://localhost:8082`

#### Required Environment Variables
The Docker Compose file is fully parameterized via `.env`:
- `BLUE_IMAGE` — Image reference for Blue service
- `GREEN_IMAGE` — Image reference for Green service
- `ACTIVE_POOL` — `blue` or `green` (controls NGINX template)
- `RELEASE_ID_BLUE` — Blue service release identifier
- `RELEASE_ID_GREEN` — Green service release identifier
- `PORT` — Application port (optional)

#### Response Headers
On every successful response, the apps include:
- `X-App-Pool`: `blue` or `green` (literal pool identity)
- `X-Release-Id`: Release identifier string


## Thought Process
1. Have I ever configured a NGINX proxy using an NGINX container? No.
2. Have I ever run Docker containers using `docker compose`? No
3. Does the first push reflect that I truly understood what was being done? No.

In order to truly understand the workings of this project, I have created a pipeline, `.github/workflows/flow.yml`, that will help me to understand more on the workings of the project. What do I seek to understand?
- The structure of a `docker compose` file
- NGINX Proxy configuration as a whole
- Reconfiguration of the script where possible- `manage.sh`

This [article](https://medium.com/@christianashedrack/building-a-zero-downtime-blue-green-deployment-with-nginx-4716f73bdec8) broke down the NGINX part, making the task much easier to understand.

#### ***Note:*** I'll document every thing as much as possible.

### CI Pipeline
*Currently triggered manually*

1. checks whether the project directory (root directory) is present in the server. The project already exists in the server hence no need to clone it via the pipeline. The pipeline then updates the directory with recent changes in the `main` branch.
2. Checks whether Docker and Docker compose exist in server and downloads latest version if not exist.

### Docker Compose - `docker-compose.yml`

### NGINX Configuration - `nginx/`

### Script - `manage.sh`



