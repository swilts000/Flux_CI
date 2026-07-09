package main

import (
	"crypto/tls"
	"embed"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

// Embed the frontend static assets.
//go:embed index.html CSS/* Script/* nginx.conf
var content embed.FS

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// BACKEND_URL is the CF route of the backend app, e.g.
	// https://todoback.apps.example.com
	// When unset, /api/ requests will 502.
	backendURL := os.Getenv("BACKEND_URL")

	mux := http.NewServeMux()

	// Proxy /api/ requests to the backend.
	if backendURL != "" {
		target, err := url.Parse(backendURL)
		if err != nil {
			log.Fatalf("invalid BACKEND_URL %q: %v", backendURL, err)
		}
		proxy := httputil.NewSingleHostReverseProxy(target)

		// CF GoRouter requires the Host header to match the backend's route.
		// Override the default Director to set Host correctly.
		defaultDirector := proxy.Director
		proxy.Director = func(r *http.Request) {
			defaultDirector(r)
			r.Host = target.Host
		}

		// CF GoRouter uses its own TLS cert; skip verification for outbound proxy calls.
		proxy.Transport = &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}

		// Surface actual proxy errors in logs and response.
		proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
			log.Printf("proxy error: %v", err)
			http.Error(w, "proxy error: "+err.Error(), http.StatusBadGateway)
		}

		mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
			proxy.ServeHTTP(w, r)
		})
		log.Printf("proxying /api/ -> %s", backendURL)
	} else {
		log.Println("BACKEND_URL not set; /api/ requests will not be proxied")
		mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, "BACKEND_URL not configured", http.StatusBadGateway)
		})
	}

	// Serve all other paths from the embedded filesystem.
	fileServer := http.FileServer(http.FS(content))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Prevent the proxy handler catching non-api paths that start differently.
		if strings.HasPrefix(r.URL.Path, "/api/") {
			http.NotFound(w, r)
			return
		}
		fileServer.ServeHTTP(w, r)
	})

	log.Printf("starting server on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

