# Build a small static Go binary that serves the frontend assets, then use distroless
FROM golang:1.20-alpine AS builder
WORKDIR /src

# Fetch modules first to leverage Docker layer caching
COPY go.mod ./
RUN apk add --no-cache git ca-certificates
RUN go mod download

# Copy remainder of sources and assets
COPY . .

# Build statically linked binary for Linux amd64
ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
RUN go build -ldflags="-s -w" -o /server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /server /server

EXPOSE 8080
USER nonroot
ENTRYPOINT ["/server"]

