# Flux Bootstrap Guide for Local Colima Kubernetes Cluster

This guide walks through bootstrapping Flux CD on a local Colima Kubernetes cluster to deploy the Todo application using GitOps.

---

## Prerequisites`

- **macOS** with Homebrew installed
- **GitHub account** with a personal access token (PAT)
- **Docker Desktop** or **Colima** installed

---

## Step 1: Install Required Tools

### 1.1 Install Colima (if not already installed)

```bash
brew install colima
```

### 1.2 Install kubectl

```bash
brew install kubectl
```

### 1.3 Install Flux CLI

```bash
brew install fluxcd/tap/flux
```

### 1.4 Verify installations

```bash
colima version
kubectl version --client
flux --version
```

---

## Step 2: Start Colima with Kubernetes

### 2.1 Start Colima with Kubernetes enabled

```bash
colima start --kubernetes --cpu 4 --memory 8 --disk 60
```

> **Note**: Adjust CPU, memory, and disk based on your machine's resources. Minimum recommended: 2 CPU, 4GB RAM.

### 2.2 Verify Kubernetes is running

```bash
kubectl cluster-info
kubectl get nodes
```

Expected output should show a single node in `Ready` state.

---

## Step 3: Build and Load Docker Images into Colima

Since Colima uses its own Docker daemon, you need to build images inside Colima's environment.

### 3.1 Set Docker context to Colima

```bash
# Colima automatically configures Docker context
docker context use colima
```

### 3.2 Build the Backend image

```bash
cd ~/Desktop/Flux_CI/todo/Backend
docker build -t backendtodo:latest .
```

### 3.3 Build the Frontend image

```bash
cd ~/Desktop/Flux_CI/todo/Frontend
docker build -t frontend:latest .
```

### 3.4 Verify images are available

```bash
docker images | grep -E "backendtodo|frontend"
```

---

## Step 4: Create GitHub Personal Access Token

Flux needs a GitHub PAT to manage your repository.

### 4.1 Create a PAT on GitHub

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**
2. Click **Generate new token (classic)**
3. Give it a descriptive name: `flux-colima-bootstrap`
4. Select scopes:
   - `repo` (full control of private repositories)
5. Click **Generate token**
6. **Copy the token** — you won't see it again!

### 4.2 Export the token as an environment variable

```bash
export GITHUB_TOKEN=<your-github-token>
export GITHUB_USER=<your-github-username>
```

---

## Step 5: Verify Flux Prerequisites

Before bootstrapping, verify your cluster meets Flux requirements:

```bash
flux check --pre
```

Expected output:
```
► checking prerequisites
✔ Kubernetes 1.xx.x >=1.25.0-0
✔ prerequisites checks passed
```

---

## Step 6: Bootstrap Flux

### 6.1 Bootstrap Flux to your GitHub repository

```bash
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=Flux_CI \
  --branch=main \
  --path=./clusters/colima \
  --personal
```

This command will:
- Install Flux components in the `flux-system` namespace
- Create the `clusters/colima` directory structure in your repo
- Configure Flux to sync from this path

### 6.2 Verify Flux installation

```bash
flux check
kubectl get pods -n flux-system
```

All pods should be in `Running` state.

---

## Step 7: Verify Flux Kustomization Files

The required kustomization files have already been created:

### 7.1 Flux Kustomization for Todo App

**File:** `clusters/colima/todo-app/kustomization.yaml`

This tells Flux to deploy resources from `./todo/k8s`:

```bash
cat ~/Desktop/Flux_CI/clusters/colima/todo-app/kustomization.yaml
```

### 7.2 K8s Kustomization

**File:** `todo/k8s/kustomization.yaml`

This lists all K8s resources to deploy:

```bash
cat ~/Desktop/Flux_CI/todo/k8s/kustomization.yaml
```

---

## Step 8: Commit and Push Changes

```bash
cd ~/Desktop/Flux_CI
git add .
git commit -m "Add Flux kustomization for todo app"
git push origin main
```

---

## Step 9: Verify Flux Reconciliation

### 9.1 Watch Flux reconcile the changes

```bash
flux get kustomizations --watch
```

### 9.2 Check the todo-app kustomization status

```bash
flux get kustomization todo-app
```

### 9.3 Verify pods are running

```bash
kubectl get pods -w
```

Wait until all pods show `Running` status:
- `mysql-*`
- `todo-api-*`
- `todo-frontend-*`

---

## Step 10: Access the Todo Application

### 10.1 Port-forward the frontend service

```bash
kubectl port-forward svc/todo-frontend 8081:80
```

### 10.2 Open in browser

Navigate to: **http://localhost:8081**

### 10.3 Test the API directly (optional)

```bash
# Port-forward backend
kubectl port-forward svc/todo-api 8080:8080

# Test API
curl http://localhost:8080/api/todos

# Create a todo
curl -X POST http://localhost:8080/api/todos \
  -H "Content-Type: application/json" \
  -d '{"text":"Test from Flux GitOps","done":false}'
```

---

## Step 11: Verify GitOps Workflow

### 11.1 Make a change to test GitOps

Edit `todo/k8s/frontend-deployment.yaml` and change replicas:

```yaml
spec:
  replicas: 2  # Changed from 1
```

### 11.2 Commit and push

```bash
git add .
git commit -m "Scale frontend to 2 replicas"
git push origin main
```

### 11.3 Watch Flux apply the change

```bash
flux reconcile kustomization todo-app --with-source
kubectl get pods -l app=todo-frontend
```

You should see 2 frontend pods after reconciliation.

---

## Useful Flux Commands

| Command | Description |
|---------|-------------|
| `flux get all` | Show all Flux resources |
| `flux get kustomizations` | List all kustomizations |
| `flux reconcile kustomization todo-app --with-source` | Force immediate sync |
| `flux logs --follow` | Stream Flux controller logs |
| `flux suspend kustomization todo-app` | Pause reconciliation |
| `flux resume kustomization todo-app` | Resume reconciliation |
| `flux events` | Show Flux events |

---

## Troubleshooting

### Flux not syncing

```bash
flux logs --follow --level=error
flux get sources git
```

### Pods not starting

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Image pull errors

Ensure images are built in Colima's Docker context:
```bash
docker context use colima
docker images
```

### MySQL connection issues

Check if MySQL is ready:
```bash
kubectl logs -l app=mysql
kubectl exec -it deploy/mysql -- mysql -u root -ppassword -e "SHOW DATABASES;"
```

### Reset everything

```bash
# Uninstall Flux
flux uninstall

# Delete all resources
kubectl delete -k todo/k8s/

# Stop Colima
colima stop

# Start fresh
colima delete
colima start --kubernetes --cpu 4 --memory 8 --disk 60
```

---

## Directory Structure After Bootstrap

```
Flux_CI/
├── clusters/
│   └── colima/
│       ├── flux-system/          # Created by Flux bootstrap
│       │   ├── gotk-components.yaml
│       │   ├── gotk-sync.yaml
│       │   └── kustomization.yaml
│       └── todo-app/
│           └── kustomization.yaml
├── todo/
│   ├── k8s/
│   │   ├── kustomization.yaml    # Added for Flux
│   │   ├── backend-deployment.yaml
│   │   ├── backend-service.yaml
│   │   ├── frontend-deployment.yaml
│   │   ├── frontend-service.yaml
│   │   ├── mysql-deployment.yaml
│   │   ├── mysql-service.yaml
│   │   ├── mysql-pvc.yaml
│   │   ├── secret.yaml
│   │   └── ...
│   ├── Backend/
│   ├── Frontend/
│   └── ...
└── FLUX_BOOTSTRAP_GUIDE.md
```

---

## Summary

You have successfully:
1. ✅ Set up Colima with Kubernetes
2. ✅ Built Docker images for the Todo app
3. ✅ Bootstrapped Flux CD to your GitHub repository
4. ✅ Created Flux Kustomizations for GitOps deployment
5. ✅ Deployed the Todo application via GitOps
6. ✅ Verified the GitOps workflow

Any changes pushed to the `main` branch will now be automatically reconciled by Flux!
