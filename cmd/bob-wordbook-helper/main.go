package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	defaultListenAddress = "127.0.0.1:19820"
	clientHeaderName     = "X-Bob-Wordbook-Client"
	clientHeaderValue    = "bob-plugin"
	maxRequestBodyBytes  = 64 << 10
)

type appendRequest struct {
	Text string `json:"text"`
	Path string `json:"path,omitempty"`
}

type entry struct {
	Text      string `json:"text"`
	CreatedAt string `json:"created_at"`
}

type appendResponse struct {
	OK    bool   `json:"ok"`
	Path  string `json:"path"`
	Entry entry  `json:"entry"`
}

type errorResponse struct {
	OK      bool   `json:"ok"`
	Message string `json:"message"`
}

type server struct {
	defaultPath string
	homeDir     string
	now         func() time.Time
	writeMu     sync.Mutex
}

func main() {
	listenAddress := flag.String("listen", defaultListenAddress, "HTTP listen address")
	defaultPathFlag := flag.String("default-path", "", "default JSONL file path")
	flag.Parse()

	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("[main] resolve user home directory failed err:%v", err)
	}

	defaultPath := strings.TrimSpace(*defaultPathFlag)
	if defaultPath == "" {
		defaultPath = filepath.Join(homeDir, "Downloads", "bob-wordbook.jsonl")
	}

	app := newServer(defaultPath, homeDir)
	resolvedDefaultPath, err := app.resolvePath("")
	if err != nil {
		log.Fatalf("[main] resolve default output path failed err:%v", err)
	}

	log.Printf("[main] start Bob Wordbook helper listen:%s, defaultPath:%s", *listenAddress, resolvedDefaultPath)
	if err := http.ListenAndServe(*listenAddress, app.routes()); err != nil {
		log.Fatalf("[main] serve HTTP failed err:%v", err)
	}
}

func newServer(defaultPath string, homeDir string) *server {
	return &server{
		defaultPath: defaultPath,
		homeDir:     homeDir,
		now:         time.Now,
	}
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealth)
	mux.HandleFunc("POST /v1/entries", s.handleAppendEntry)
	return mux
}

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) handleAppendEntry(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Origin") != "" {
		writeJSON(w, http.StatusForbidden, errorResponse{Message: "browser-origin requests are not allowed"})
		return
	}
	if r.Header.Get(clientHeaderName) != clientHeaderValue {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Message: "invalid client header"})
		return
	}

	var request appendRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRequestBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: fmt.Sprintf("invalid JSON body: %v", err)})
		return
	}
	if err := ensureJSONBodyEnded(decoder); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return
	}

	text := strings.TrimSpace(request.Text)
	if text == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "text must not be empty"})
		return
	}

	outputPath, err := s.resolvePath(request.Path)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return
	}

	wordbookEntry := entry{
		Text:      text,
		CreatedAt: s.now().Format(time.RFC3339Nano),
	}
	if err := s.appendEntry(outputPath, wordbookEntry); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Message: fmt.Sprintf("append entry: %v", err)})
		return
	}

	writeJSON(w, http.StatusCreated, appendResponse{
		OK:    true,
		Path:  outputPath,
		Entry: wordbookEntry,
	})
}

func (s *server) appendEntry(outputPath string, wordbookEntry entry) error {
	line, err := json.Marshal(wordbookEntry)
	if err != nil {
		return fmt.Errorf("encode JSONL entry: %w", err)
	}
	line = append(line, '\n')

	s.writeMu.Lock()
	defer s.writeMu.Unlock()

	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return fmt.Errorf("create output directory: %w", err)
	}

	file, err := os.OpenFile(outputPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return fmt.Errorf("open output file: %w", err)
	}

	if _, err := file.Write(line); err != nil {
		closeErr := file.Close()
		if closeErr != nil {
			return fmt.Errorf("write output file: %w; close output file: %v", err, closeErr)
		}
		return fmt.Errorf("write output file: %w", err)
	}
	if err := file.Sync(); err != nil {
		closeErr := file.Close()
		if closeErr != nil {
			return fmt.Errorf("sync output file: %w; close output file: %v", err, closeErr)
		}
		return fmt.Errorf("sync output file: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close output file: %w", err)
	}

	return nil
}

func (s *server) resolvePath(configuredPath string) (string, error) {
	outputPath := strings.TrimSpace(configuredPath)
	if outputPath == "" {
		outputPath = strings.TrimSpace(s.defaultPath)
	}

	if outputPath == "~" {
		outputPath = s.homeDir
	} else if strings.HasPrefix(outputPath, "~/") {
		outputPath = filepath.Join(s.homeDir, strings.TrimPrefix(outputPath, "~/"))
	}

	outputPath = filepath.Clean(outputPath)
	if !filepath.IsAbs(outputPath) {
		return "", errors.New("path must be absolute or start with ~/")
	}
	if !strings.EqualFold(filepath.Ext(outputPath), ".jsonl") {
		return "", errors.New("path must point to a .jsonl file")
	}

	return outputPath, nil
}

func ensureJSONBodyEnded(decoder *json.Decoder) error {
	var extra any
	err := decoder.Decode(&extra)
	if errors.Is(err, io.EOF) {
		return nil
	}
	if err == nil {
		return errors.New("JSON body must contain exactly one object")
	}
	return fmt.Errorf("invalid JSON body: %w", err)
}

func writeJSON(w http.ResponseWriter, statusCode int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(statusCode)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("[writeJSON] encode response failed err:%v", err)
	}
}
