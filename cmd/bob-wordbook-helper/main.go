package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"mime"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unicode"
)

const (
	defaultListenAddress = "127.0.0.1:19820"
	clientHeaderName     = "X-Bob-Wordbook-Client"
	clientHeaderValue    = "bob-plugin"
	maxRequestBodyBytes  = 64 << 10
	shutdownTimeout      = 5 * time.Second
	helperWriteTimeout   = 110 * time.Second
)

var version = "dev"

type appendRequest struct {
	Text string `json:"text"`
	Path string `json:"path,omitempty"`
}

type appendLearningRequest struct {
	Text           string `json:"text"`
	Result         string `json:"result"`
	SourceLanguage string `json:"source_language"`
	TargetLanguage string `json:"target_language"`
	Provider       string `json:"provider"`
	Model          string `json:"model"`
	Path           string `json:"path,omitempty"`
}

type appendStructuredLearningRequest struct {
	Text           string          `json:"text"`
	Kind           string          `json:"kind"`
	Content        learningContent `json:"content"`
	SourceLanguage string          `json:"source_language"`
	TargetLanguage string          `json:"target_language"`
	Provider       string          `json:"provider"`
	Model          string          `json:"model"`
	Path           string          `json:"path,omitempty"`
}

type learningContent struct {
	Text         string            `json:"text,omitempty"`
	Word         string            `json:"word,omitempty"`
	Phonetics    []phonetic        `json:"phonetics,omitempty"`
	Parts        []wordPart        `json:"parts,omitempty"`
	Collocations []collocation     `json:"collocations,omitempty"`
	Examples     []exampleSentence `json:"examples,omitempty"`
}

type phonetic struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

type wordPart struct {
	Part  string   `json:"part"`
	Means []string `json:"means"`
}

type collocation struct {
	Text    string `json:"text"`
	Meaning string `json:"meaning"`
}

type exampleSentence struct {
	Text        string `json:"text"`
	Translation string `json:"translation"`
}

type entry struct {
	Text      string `json:"text"`
	CreatedAt string `json:"created_at"`
}

type learningEntry struct {
	SchemaVersion  int    `json:"schema_version"`
	Text           string `json:"text"`
	Result         string `json:"result"`
	SourceLanguage string `json:"source_language"`
	TargetLanguage string `json:"target_language"`
	Provider       string `json:"provider"`
	Model          string `json:"model"`
	CreatedAt      string `json:"created_at"`
}

type structuredLearningEntry struct {
	SchemaVersion  int             `json:"schema_version"`
	Text           string          `json:"text"`
	Kind           string          `json:"kind"`
	Content        learningContent `json:"content"`
	SourceLanguage string          `json:"source_language"`
	TargetLanguage string          `json:"target_language"`
	Provider       string          `json:"provider"`
	Model          string          `json:"model"`
	CreatedAt      string          `json:"created_at"`
}

type appendResponse struct {
	OK    bool   `json:"ok"`
	Path  string `json:"path"`
	Entry entry  `json:"entry"`
}

type appendLearningResponse struct {
	OK    bool          `json:"ok"`
	Path  string        `json:"path"`
	Entry learningEntry `json:"entry"`
}

type appendStructuredLearningResponse struct {
	OK    bool                    `json:"ok"`
	Path  string                  `json:"path"`
	Entry structuredLearningEntry `json:"entry"`
}

type errorResponse struct {
	OK      bool   `json:"ok"`
	Message string `json:"message"`
}

type server struct {
	defaultPath          string
	homeDir              string
	now                  func() time.Time
	writeMu              sync.Mutex
	codexRequestSequence atomic.Uint64
	codex                *codexService
}

func main() {
	listenAddress := flag.String("listen", defaultListenAddress, "HTTP listen address")
	defaultPathFlag := flag.String("default-path", "", "default JSONL file path")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()
	if *showVersion {
		fmt.Println(version)
		return
	}
	if err := validateListenAddress(*listenAddress); err != nil {
		log.Fatalf("[main] validate listen address failed err:%v", err)
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Fatalf("[main] resolve user home directory failed err:%v", err)
	}

	defaultPath := strings.TrimSpace(*defaultPathFlag)
	if defaultPath == "" {
		defaultPath = filepath.Join(homeDir, "Downloads", "bob-wordbook.jsonl")
	}

	app := newServer(defaultPath, homeDir)
	defer app.codex.closeAppServer()
	resolvedDefaultPath, err := app.resolvePath("")
	if err != nil {
		log.Fatalf("[main] resolve default output path failed err:%v", err)
	}

	httpServer := &http.Server{
		Addr:              *listenAddress,
		Handler:           app.routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      helperWriteTimeout,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    8 << 10,
	}

	log.Printf("[main] start Bob Wordbook helper version:%s, listen:%s, defaultPath:%s", version, *listenAddress, resolvedDefaultPath)
	go func() {
		warmContext, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := app.codex.warmAppServer(warmContext); err != nil {
			log.Printf("[codex.app-server] warm-up skipped err:%v", err)
		}
	}()
	if err := serveUntilSignal(httpServer); err != nil {
		log.Fatalf("[main] serve HTTP failed err:%v", err)
	}
}

func serveUntilSignal(httpServer *http.Server) error {
	serveErr := make(chan error, 1)
	go func() {
		serveErr <- httpServer.ListenAndServe()
	}()

	signalContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	select {
	case err := <-serveErr:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-signalContext.Done():
		shutdownContext, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		return httpServer.Shutdown(shutdownContext)
	}
}

func newServer(defaultPath string, homeDir string) *server {
	return &server{
		defaultPath: defaultPath,
		homeDir:     homeDir,
		now:         time.Now,
		codex:       newCodexService(homeDir),
	}
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealth)
	mux.HandleFunc("POST /v1/entries", s.handleAppendEntry)
	mux.HandleFunc("POST /v2/entries", s.handleAppendLearningEntry)
	mux.HandleFunc("POST /v3/entries", s.handleAppendStructuredLearningEntry)
	mux.HandleFunc("GET /v1/codex/status", s.handleCodexStatus)
	mux.HandleFunc("POST /v1/codex/translate", s.handleCodexTranslate)
	mux.HandleFunc("POST /v1/codex/translate/stream", s.handleCodexTranslateStream)
	return mux
}

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "version": version})
}

func (s *server) handleAppendEntry(w http.ResponseWriter, r *http.Request) {
	var request appendRequest
	if !decodeAppendRequest(w, r, &request) {
		return
	}

	text := strings.TrimSpace(request.Text)
	if text == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "text must not be empty"})
		return
	}
	if err := validateEnglishText(text); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
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
	if err := s.appendJSONL(outputPath, wordbookEntry); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Message: fmt.Sprintf("append entry: %v", err)})
		return
	}

	writeJSON(w, http.StatusCreated, appendResponse{
		OK:    true,
		Path:  outputPath,
		Entry: wordbookEntry,
	})
}

func (s *server) handleAppendLearningEntry(w http.ResponseWriter, r *http.Request) {
	var request appendLearningRequest
	if !decodeAppendRequest(w, r, &request) {
		return
	}

	text := strings.TrimSpace(request.Text)
	if text == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "text must not be empty"})
		return
	}
	if err := validateEnglishText(text); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return
	}

	result := strings.TrimSpace(request.Result)
	if result == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "result must not be empty"})
		return
	}
	if request.SourceLanguage != "en" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "source_language must be en"})
		return
	}
	targetLanguage := strings.TrimSpace(request.TargetLanguage)
	if targetLanguage == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "target_language must not be empty"})
		return
	}
	if err := validateProvider(request.Provider); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return
	}
	model := strings.TrimSpace(request.Model)
	if model == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "model must not be empty"})
		return
	}

	outputPath, err := s.resolvePath(request.Path)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return
	}

	wordbookEntry := learningEntry{
		SchemaVersion:  2,
		Text:           text,
		Result:         result,
		SourceLanguage: request.SourceLanguage,
		TargetLanguage: targetLanguage,
		Provider:       request.Provider,
		Model:          model,
		CreatedAt:      s.now().Format(time.RFC3339Nano),
	}
	if err := s.appendJSONL(outputPath, wordbookEntry); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Message: fmt.Sprintf("append learning entry: %v", err)})
		return
	}

	writeJSON(w, http.StatusCreated, appendLearningResponse{
		OK:    true,
		Path:  outputPath,
		Entry: wordbookEntry,
	})
}

func (s *server) handleAppendStructuredLearningEntry(w http.ResponseWriter, r *http.Request) {
	var request appendStructuredLearningRequest
	if !decodeAppendRequest(w, r, &request) {
		return
	}

	text := strings.TrimSpace(request.Text)
	if text == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "text must not be empty"})
		return
	}
	if err := validateEnglishText(text); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return
	}

	kind := strings.TrimSpace(request.Kind)
	content, err := normalizeLearningContent(kind, text, request.Content)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return
	}
	if request.SourceLanguage != "en" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "source_language must be en"})
		return
	}
	targetLanguage := strings.TrimSpace(request.TargetLanguage)
	if targetLanguage == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "target_language must not be empty"})
		return
	}
	if err := validateProvider(request.Provider); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return
	}
	model := strings.TrimSpace(request.Model)
	if model == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: "model must not be empty"})
		return
	}

	outputPath, err := s.resolvePath(request.Path)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return
	}

	wordbookEntry := structuredLearningEntry{
		SchemaVersion:  3,
		Text:           text,
		Kind:           kind,
		Content:        content,
		SourceLanguage: request.SourceLanguage,
		TargetLanguage: targetLanguage,
		Provider:       request.Provider,
		Model:          model,
		CreatedAt:      s.now().Format(time.RFC3339Nano),
	}
	if err := s.appendJSONL(outputPath, wordbookEntry); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Message: fmt.Sprintf("append structured learning entry: %v", err)})
		return
	}

	writeJSON(w, http.StatusCreated, appendStructuredLearningResponse{
		OK:    true,
		Path:  outputPath,
		Entry: wordbookEntry,
	})
}

func normalizeLearningContent(kind string, sourceText string, content learningContent) (learningContent, error) {
	switch kind {
	case "text":
		content.Text = strings.TrimSpace(content.Text)
		if content.Text == "" {
			return learningContent{}, errors.New("content.text must not be empty for text entries")
		}
		if content.Word != "" || len(content.Phonetics) != 0 || len(content.Parts) != 0 ||
			len(content.Collocations) != 0 || len(content.Examples) != 0 {
			return learningContent{}, errors.New("text entries must not contain word fields")
		}
		return learningContent{Text: content.Text}, nil
	case "word":
		if strings.TrimSpace(content.Text) != "" {
			return learningContent{}, errors.New("word entries must not contain content.text")
		}
		content.Word = strings.TrimSpace(content.Word)
		if content.Word != sourceText {
			return learningContent{}, errors.New("content.word must match text")
		}
		if len(content.Parts) == 0 {
			return learningContent{}, errors.New("content.parts must not be empty for word entries")
		}
		if err := normalizeWordContent(&content); err != nil {
			return learningContent{}, err
		}
		return content, nil
	default:
		return learningContent{}, errors.New("kind must be word or text")
	}
}

func normalizeWordContent(content *learningContent) error {
	if len(content.Phonetics) > 2 || len(content.Parts) > 4 || len(content.Collocations) > 3 || len(content.Examples) > 2 {
		return errors.New("word content exceeds the supported item limits")
	}
	for index := range content.Phonetics {
		content.Phonetics[index].Type = strings.TrimSpace(content.Phonetics[index].Type)
		content.Phonetics[index].Value = strings.TrimSpace(content.Phonetics[index].Value)
		if content.Phonetics[index].Type != "us" && content.Phonetics[index].Type != "uk" {
			return errors.New("phonetic type must be us or uk")
		}
		if content.Phonetics[index].Value == "" {
			return errors.New("phonetic value must not be empty")
		}
	}
	for index := range content.Parts {
		content.Parts[index].Part = strings.TrimSpace(content.Parts[index].Part)
		if content.Parts[index].Part == "" || len(content.Parts[index].Means) == 0 || len(content.Parts[index].Means) > 4 {
			return errors.New("each word part must have a part and one to four meanings")
		}
		for meanIndex := range content.Parts[index].Means {
			content.Parts[index].Means[meanIndex] = strings.TrimSpace(content.Parts[index].Means[meanIndex])
			if content.Parts[index].Means[meanIndex] == "" {
				return errors.New("word meanings must not be empty")
			}
		}
	}
	for index := range content.Collocations {
		content.Collocations[index].Text = strings.TrimSpace(content.Collocations[index].Text)
		content.Collocations[index].Meaning = strings.TrimSpace(content.Collocations[index].Meaning)
		if content.Collocations[index].Text == "" || content.Collocations[index].Meaning == "" {
			return errors.New("collocations must include text and meaning")
		}
	}
	for index := range content.Examples {
		content.Examples[index].Text = strings.TrimSpace(content.Examples[index].Text)
		content.Examples[index].Translation = strings.TrimSpace(content.Examples[index].Translation)
		if content.Examples[index].Text == "" || content.Examples[index].Translation == "" {
			return errors.New("examples must include text and translation")
		}
	}
	return nil
}

func decodeAppendRequest(w http.ResponseWriter, r *http.Request, destination any) bool {
	if r.Header.Get("Origin") != "" {
		writeJSON(w, http.StatusForbidden, errorResponse{Message: "browser-origin requests are not allowed"})
		return false
	}
	if r.Header.Get(clientHeaderName) != clientHeaderValue {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Message: "invalid client header"})
		return false
	}
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || mediaType != "application/json" {
		writeJSON(w, http.StatusUnsupportedMediaType, errorResponse{Message: "Content-Type must be application/json"})
		return false
	}

	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRequestBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: fmt.Sprintf("invalid JSON body: %v", err)})
		return false
	}
	if err := ensureJSONBodyEnded(decoder); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Message: err.Error()})
		return false
	}
	return true
}

func (s *server) appendJSONL(outputPath string, value any) error {
	line, err := json.Marshal(value)
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

func validateEnglishText(text string) error {
	hasEnglishLetter := false
	for _, character := range text {
		if unicode.Is(unicode.Han, character) {
			return errors.New("text must not contain Chinese characters")
		}
		if character >= 'A' && character <= 'Z' || character >= 'a' && character <= 'z' {
			hasEnglishLetter = true
		}
	}
	if !hasEnglishLetter {
		return errors.New("text must contain an English letter")
	}
	return nil
}

func validateProvider(provider string) error {
	if provider != "aihubmix" && provider != "local_codex" {
		return errors.New("provider must be aihubmix or local_codex")
	}
	return nil
}

func (s *server) resolvePath(configuredPath string) (string, error) {
	outputPath := strings.TrimSpace(configuredPath)
	if outputPath == "" {
		outputPath = strings.TrimSpace(s.defaultPath)
	}
	if strings.ContainsRune(outputPath, '\\') {
		return "", errors.New("path must not contain backslashes; enter the path without shell escaping")
	}

	if outputPath == "~" {
		outputPath = s.homeDir
	} else if strings.HasPrefix(outputPath, "~/") {
		outputPath = filepath.Join(s.homeDir, strings.TrimPrefix(outputPath, "~/"))
	}

	outputPath = filepath.Clean(outputPath)
	for _, component := range strings.Split(outputPath, string(filepath.Separator)) {
		if strings.HasPrefix(component, "~") {
			return "", errors.New("path contains a misplaced ~; use ~ only at the beginning as ~/")
		}
	}
	if !filepath.IsAbs(outputPath) {
		return "", errors.New("path must be absolute or start with ~/")
	}
	if !strings.EqualFold(filepath.Ext(outputPath), ".jsonl") {
		return "", errors.New("path must point to a .jsonl file")
	}

	return outputPath, nil
}

func validateListenAddress(address string) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return fmt.Errorf("parse address: %w", err)
	}
	if strings.EqualFold(host, "localhost") {
		return nil
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return errors.New("listen address must use a loopback host")
	}
	return nil
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
