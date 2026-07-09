# Cloud Foundry Deployment Notes

## Prerequisites
- `cf` CLI installed and logged in (`cf login`)
- MySQL running as a CF Docker app named `todo-mysql`
- Backend JAR built (`cd Backend && ./mvnw clean package -DskipTests`)

---

## Deploy MySQL as a CF Docker App

```bash
cf push todo-mysql -f manifest-mysql.yml
```

---

## Deploy the Backend JAR to CF

### 1. Enable container-to-container networking so the backend can reach MySQL on port 3306

```bash
# Map an internal DNS hostname to the MySQL CF app
cf map-route todo-mysql apps.internal --hostname todo-mysql

# Open a network policy allowing the backend to talk to MySQL on TCP 3306
cf add-network-policy todoback todo-mysql --port 3306 --protocol tcp
```

- `apps.internal` is CF's private DNS — only reachable between CF apps, not from the internet.
- Without `cf add-network-policy`, the overlay network blocks all inter-app traffic.

### 2. Push the backend JAR

```bash
cd Backend
cf push todoback \
  -p target/todo-0.0.1-SNAPSHOT.jar \
  -b java_buildpack \
  -m 1G \
  --no-start
```

- `-b java_buildpack` — uses the CF system Java buildpack.
- `--no-start` — prevents the app starting before env vars are set.

### 3. Set environment variables

```bash
# Request Java 17 from the CF Java buildpack (app is compiled to class file version 61 / Java 17)
cf set-env todoback JBP_CONFIG_OPEN_JDK_JRE '{ jre: { version: 17.+ } }'

# Spring profile
cf set-env todoback SPRING_PROFILES_ACTIVE cloud

# Database connection — use the internal hostname from step 1
cf set-env todoback SPRING_DATASOURCE_URL "jdbc:mysql://todo-mysql.apps.internal:3306/tododb"
cf set-env todoback SPRING_DATASOURCE_USERNAME root
cf set-env todoback SPRING_DATASOURCE_PASSWORD password
cf set-env todoback SPRING_DATASOURCE_DRIVER_CLASS_NAME com.mysql.cj.jdbc.Driver
```

- `JBP_CONFIG_OPEN_JDK_JRE` is required because the default CF JRE is Java 8, which cannot run a Java 17 JAR (`UnsupportedClassVersionError` class file version 61).
- `todo-mysql.apps.internal` resolves only inside CF — CF's GoRouter cannot proxy raw TCP, so a public route for MySQL would not work.

### 4. Start the app

```bash
cf start todoback
```

### 5. Verify

```bash
cf apps                    # confirm todoback is running
cf network-policies        # confirm todoback -> todo-mysql :3306 policy exists
cf env todoback            # confirm env vars are set correctly
cf logs todoback --recent  # look for HikariPool startup success
```

---

---

## Deploy the Frontend to CF (binary_buildpack approach)

The frontend is a Go binary that serves embedded static files and reverse-proxies
`/api/` calls to the backend. No Docker registry is needed — the compiled Linux binary
is pushed directly using `binary_buildpack`.

### Why binary_buildpack?
- No Docker registry required — push the compiled binary directly.
- No `go_buildpack` / stack errors.
- CF provides `PORT` at runtime; the binary reads it from `os.Getenv("PORT")`.
- No `PORT` in manifest needed — CF injects it automatically.

### 1. Build the Linux binary using Docker (no local Go install needed)

```bash
# from repo root
docker run --rm \
  -v "$PWD/Frontend":/src \
  -w /src \
  golang:1.20-alpine \
  sh -c "apk add --no-cache git && env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags='-s -w' -o todo-frontend ."

# confirm binary exists
ls -lh Frontend/todo-frontend
```

### 2. Ensure a Procfile exists in Frontend/

`Frontend/Procfile` must contain:
```
web: ./todo-frontend
```

### 3. Push to CF

```bash
cf push todo-frontend -f manifest-frontend.yml
cf logs todo-frontend --recent
```

`manifest-frontend.yml`:
```yaml
applications:
- name: todo-frontend
  path: Frontend
  buildpack: binary_buildpack
  memory: 128M
  env:
    BACKEND_URL: https://todoback.pob-t1.cf.comcast.net
```

- `BACKEND_URL` is the public CF route of the backend — the Go binary proxies
  all `/api/` requests server-side to this URL.
- Do **not** set `PORT` — CF injects it automatically.

### 4. Key proxy fix — Host header + TLS

CF's GoRouter requires the outgoing `Host` header to match the backend route, and uses
its own TLS certificate. The proxy in `main.go` handles both:
- Sets `r.Host = target.Host` via a custom `Director`.
- Uses `InsecureSkipVerify: true` on the transport to accept CF's TLS cert.

Without these, requests return `400 Bad Request` (wrong Host) or `502` (TLS rejection).

### 5. Verify

```bash
cf apps                                    # all three apps running
cf app todo-frontend                       # confirm running state

# test static page
curl https://todo-frontend.pob-t1.cf.comcast.net

# test proxy to backend
curl https://todo-frontend.pob-t1.cf.comcast.net/api/todos

# test adding a todo via proxy
curl -X POST https://todo-frontend.pob-t1.cf.comcast.net/api/todos \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"test todo\",\"done\":false}"
```

### Local dev (docker-compose)

`docker-compose.yml` sets `BACKEND_URL=http://backend:8080` so the proxy works
on the Docker internal network:

```bash
docker-compose build
docker-compose up -d
# frontend: http://localhost:8081
# backend:  http://localhost:8080
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `UnsupportedClassVersionError class file version 61` | CF using Java 8, app built for Java 17 | Set `JBP_CONFIG_OPEN_JDK_JRE: '{ jre: { version: 17.+ } }'` |
| `Buildpack must be an existing admin buildpack` | Invalid buildpack name | Remove `buildpack:` from manifest to auto-detect, or use git URI |
| `Stack must be an existing stack` | `cflinuxfs3` not available | Remove `stack:` line from manifest |
| Connection refused to MySQL | No network policy | Run `cf add-network-policy` and `cf map-route ... apps.internal` |
| `PORT` env var rejected | CF reserves `PORT` | Remove `PORT` from frontend manifest env block |
| `Buildpack cannot be configured for a docker lifecycle app` | App was previously pushed as Docker | Run `cf delete todo-frontend` then re-push |
| `zip: not a valid zip file` | `path:` pointed at a raw binary file | Set `path:` to the directory, use `Procfile` to start the binary |
| `/todo-frontend: No such file or directory` (CF SSH) | Binary not built before push | Build with Docker `golang:1.20-alpine` then re-push |
| `400 Bad Request` from HAProxy | Proxy not setting correct `Host` header | Add custom `Director` in `main.go` to set `r.Host = target.Host` |
| `502` on `/api/` calls | Go default transport rejects CF TLS cert | Set `InsecureSkipVerify: true` on proxy transport |
| `Failed getting docker image manifest … access denied` | Docker image placeholder not replaced | Build and push real image, or use `binary_buildpack` instead |
