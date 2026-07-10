# Todo App Deployment Fixes - CNAP Cluster

This document details the issues encountered and fixes applied when deploying the Todo application to the CNAP cluster `cnap-ws-test-wl-a-vs-wc`.

---

## Overview

**Target Cluster:** `cnap-ws-test-wl-a-vs-wc`  
**Namespace:** `testswilts`  
**Registry:** `hub.comcast.net/sandbox`

---

## Issue 1: Duplicate Secret Definition

### Problem
Kustomize failed with error:
```
accumulation err='merging resources from 'todo-secret.yaml': may not add resource with an already registered id: Secret.v1.[noGrp]/todo-secret.[noNs]'
```

### Cause
Two files defined the same Kubernetes Secret (`todo-secret`):
- `todo/k8s/secret.yaml`
- `todo/k8s/todo-secret.yaml`

### Fix
Removed `todo-secret.yaml` from `todo/k8s/kustomization.yaml`:

```yaml
# Before
resources:
  - secret.yaml
  - todo-secret.yaml  # Duplicate!
  - configmap.yaml
  ...

# After
resources:
  - secret.yaml
  - configmap.yaml
  ...
```

**File Modified:** `todo/k8s/kustomization.yaml`

---

## Issue 2: Images Not in Registry (ErrImagePull)

### Problem
Pods failed with `ErrImagePull`:
```
Failed to pull image "frontend:latest": ... not found
Failed to pull image "backendtodo:latest": ... not found
```

### Cause
The deployment manifests referenced local image names (`frontend:latest`, `backendtodo:latest`) that don't exist in any container registry accessible by the CNAP cluster.

### Fix
1. Updated deployment manifests to use the Atlus registry (`hub.comcast.net/sandbox`)
2. Built and pushed images to the registry

**Files Modified:**
- `todo/k8s/frontend-deployment.yaml`
- `todo/k8s/backend-deployment.yaml`

```yaml
# Before
image: frontend:latest

# After
image: hub.comcast.net/sandbox/todo-frontend:v2
```

```yaml
# Before
image: backendtodo:latest

# After
image: hub.comcast.net/sandbox/todo-backend:latest
```

---

## Issue 3: Missing Backend Source Code

### Problem
Docker build failed:
```
ERROR [build 3/5] COPY pom.xml ./
ERROR [build 4/5] COPY src ./src
"/src": not found
```

### Cause
The `Backend/` directory was missing the Java source code (`src/` directory and proper `pom.xml`). Only an archetype placeholder existed.

### Fix
Created a complete Spring Boot backend application:

**Files Created:**
- `todo/Backend/pom.xml` - Maven configuration with Spring Boot dependencies
- `todo/Backend/src/main/java/com/example/todo/TodoApplication.java` - Main application class
- `todo/Backend/src/main/java/com/example/todo/Todo.java` - JPA Entity
- `todo/Backend/src/main/java/com/example/todo/TodoRepository.java` - Spring Data repository
- `todo/Backend/src/main/java/com/example/todo/TodoController.java` - REST controller
- `todo/Backend/src/main/resources/application.properties` - Database configuration

### Backend Architecture
```
Backend/
├── Dockerfile
├── pom.xml
└── src/main/
    ├── java/com/example/todo/
    │   ├── TodoApplication.java    # @SpringBootApplication entry point
    │   ├── Todo.java               # @Entity with id, text, done fields
    │   ├── TodoRepository.java     # JpaRepository<Todo, Long>
    │   └── TodoController.java     # REST endpoints at /api/todos
    └── resources/
        └── application.properties  # MySQL datasource config
```

---

## Issue 4: Wrong CPU Architecture (Platform Mismatch)

### Problem
Pods failed with `ErrImagePull`:
```
Failed to pull image "hub.comcast.net/sandbox/todo-frontend:latest": 
no match for platform in manifest: not found
```

### Cause
Images were built on an Apple Silicon Mac (ARM64/aarch64), but the CNAP cluster runs on AMD64/x86_64 nodes.

### Fix
Rebuilt images with explicit platform flag:

```bash
docker build --platform linux/amd64 -t hub.comcast.net/sandbox/todo-backend:latest .
docker build --platform linux/amd64 -f Dockerfile.amd64 -t hub.comcast.net/sandbox/todo-frontend:v2 .
```

---

## Issue 5: Binary Permission Denied (RunContainerError)

### Problem
Frontend pod failed with `RunContainerError`:
```
exec: "/server": permission denied
```

### Cause
The Go binary (`todo-frontend-amd64`) copied into the distroless container didn't have execute permissions. The `--chmod=755` flag in `COPY` doesn't work reliably with distroless images.

### Fix
Modified `Dockerfile.amd64` to use a builder stage that sets permissions:

```dockerfile
# Before (didn't work)
FROM gcr.io/distroless/static:nonroot
COPY --chmod=755 todo-frontend-amd64 /server
...

# After (working)
FROM alpine:3.19 AS builder
COPY todo-frontend-amd64 /server
RUN chmod +x /server

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /server /server
...
```

**File Modified:** `todo/Frontend/Dockerfile.amd64`

### Why This Works
- Distroless images have no shell, so `chmod` can't run inside them
- Alpine builder stage has a shell and can run `chmod +x`
- Multi-stage build copies the now-executable binary to the final image

---

## Issue 6: Cached Image with Old Permissions

### Problem
After fixing the Dockerfile, pods still failed with permission denied.

### Cause
Kubernetes nodes had cached the old `:latest` image with incorrect permissions.

### Fix
Used a new image tag (`v2`) to force pulling the corrected image:

```yaml
# Before
image: hub.comcast.net/sandbox/todo-frontend:latest

# After  
image: hub.comcast.net/sandbox/todo-frontend:v2
```

**File Modified:** `todo/k8s/frontend-deployment.yaml`

---

## Registry Authentication

### Created Login Script
`hub-comcast-login.sh` - Prompts for username and token to authenticate with Atlus registry:

```bash
./hub-comcast-login.sh
# Enter username: SWilts000
# Enter token: <your-token>
```

---

## Final Working Configuration

### Images in Registry
| Image | Tag | Platform |
|-------|-----|----------|
| `hub.comcast.net/sandbox/todo-frontend` | v2 | linux/amd64 |
| `hub.comcast.net/sandbox/todo-backend` | latest | linux/amd64 |

### Kubernetes Resources Deployed
| Resource | Name | Status |
|----------|------|--------|
| Deployment | mysql | Running |
| Deployment | todo-api | Running |
| Deployment | todo-frontend | Running |
| Service | mysql | ClusterIP:3306 |
| Service | todo-api | ClusterIP:8080 |
| Service | todo-frontend | ClusterIP:80 |
| PVC | mysql-pvc | Bound |
| Secret | todo-secret | Created |
| ConfigMap | todo-config | Created |

### Access Commands
```bash
# Frontend UI
kubectl port-forward svc/todo-frontend 8081:80
# Open http://localhost:8081

# Backend API
kubectl port-forward svc/todo-api 8080:8080
# curl http://localhost:8080/api/todos
```

---

## Lessons Learned

1. **Always specify platform** when building for remote clusters: `--platform linux/amd64`
2. **Use versioned tags** instead of `:latest` to avoid cache issues
3. **Distroless images need multi-stage builds** for permission changes
4. **Check for duplicate resources** in kustomization files
5. **Verify source code exists** before attempting Docker builds
6. **Registry authentication** must be configured before pushing images

---

## Build Commands Reference

```bash
# Login to registry
./hub-comcast-login.sh

# Build backend (from todo/Backend/)
docker build --platform linux/amd64 -t hub.comcast.net/sandbox/todo-backend:latest .

# Build frontend (from todo/Frontend/)
docker build --platform linux/amd64 -f Dockerfile.amd64 -t hub.comcast.net/sandbox/todo-frontend:v2 .

# Push images
docker push hub.comcast.net/sandbox/todo-backend:latest
docker push hub.comcast.net/sandbox/todo-frontend:v2

# Deploy
kubectl apply -k todo/k8s/

# Verify
kubectl get pods -w
```
