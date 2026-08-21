package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestAppendEntriesToDefaultJSONL(t *testing.T) {
	tempDir := t.TempDir()
	outputPath := filepath.Join(tempDir, "Downloads", "bob-wordbook.jsonl")
	app := newServer(outputPath, tempDir)
	app.now = func() time.Time {
		return time.Date(2026, time.August, 22, 10, 30, 0, 0, time.FixedZone("CST", 8*60*60))
	}

	for _, text := range []string{"hello", "take care"} {
		response := postEntry(t, app.routes(), appendRequest{Text: text})
		if response.Code != http.StatusCreated {
			t.Fatalf("status code = %d, body = %s", response.Code, response.Body.String())
		}
	}

	file, err := os.Open(outputPath)
	if err != nil {
		t.Fatalf("open output file: %v", err)
	}
	defer func() {
		if err := file.Close(); err != nil {
			t.Errorf("close output file: %v", err)
		}
	}()

	var entries []entry
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		var wordbookEntry entry
		if err := json.Unmarshal(scanner.Bytes(), &wordbookEntry); err != nil {
			t.Fatalf("decode JSONL entry: %v", err)
		}
		entries = append(entries, wordbookEntry)
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("scan output file: %v", err)
	}

	if len(entries) != 2 {
		t.Fatalf("entry count = %d, want 2", len(entries))
	}
	if entries[0].Text != "hello" || entries[1].Text != "take care" {
		t.Fatalf("entry texts = %#v", entries)
	}
	if entries[0].CreatedAt != "2026-08-22T10:30:00+08:00" {
		t.Fatalf("created_at = %q", entries[0].CreatedAt)
	}
}

func TestAppendEntryExpandsHomePath(t *testing.T) {
	tempDir := t.TempDir()
	app := newServer("~/Downloads/default.jsonl", tempDir)

	response := postEntry(t, app.routes(), appendRequest{
		Text: "piece of cake",
		Path: "~/Documents/english.jsonl",
	})
	if response.Code != http.StatusCreated {
		t.Fatalf("status code = %d, body = %s", response.Code, response.Body.String())
	}

	expectedPath := filepath.Join(tempDir, "Documents", "english.jsonl")
	if _, err := os.Stat(expectedPath); err != nil {
		t.Fatalf("stat custom output file: %v", err)
	}
}

func TestAppendEntryRejectsInvalidRequests(t *testing.T) {
	tempDir := t.TempDir()
	app := newServer(filepath.Join(tempDir, "default.jsonl"), tempDir)
	tests := []struct {
		name        string
		request     appendRequest
		origin      string
		contentType string
		withHeader  bool
		wantStatus  int
	}{
		{name: "empty text", request: appendRequest{}, withHeader: true, wantStatus: http.StatusBadRequest},
		{name: "relative path", request: appendRequest{Text: "hello", Path: "words.jsonl"}, withHeader: true, wantStatus: http.StatusBadRequest},
		{name: "wrong extension", request: appendRequest{Text: "hello", Path: "/tmp/words.json"}, withHeader: true, wantStatus: http.StatusBadRequest},
		{name: "missing client header", request: appendRequest{Text: "hello"}, wantStatus: http.StatusUnauthorized},
		{name: "browser origin", request: appendRequest{Text: "hello"}, origin: "https://example.com", withHeader: true, wantStatus: http.StatusForbidden},
		{
			name: "wrong content type", request: appendRequest{Text: "hello"}, contentType: "text/plain", withHeader: true,
			wantStatus: http.StatusUnsupportedMediaType,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			body, err := json.Marshal(test.request)
			if err != nil {
				t.Fatalf("encode request: %v", err)
			}
			request := httptest.NewRequest(http.MethodPost, "/v1/entries", bytes.NewReader(body))
			contentType := test.contentType
			if contentType == "" {
				contentType = "application/json"
			}
			request.Header.Set("Content-Type", contentType)
			if test.withHeader {
				request.Header.Set(clientHeaderName, clientHeaderValue)
			}
			if test.origin != "" {
				request.Header.Set("Origin", test.origin)
			}

			response := httptest.NewRecorder()
			app.routes().ServeHTTP(response, request)
			if response.Code != test.wantStatus {
				t.Fatalf("status code = %d, want %d, body = %s", response.Code, test.wantStatus, response.Body.String())
			}
		})
	}
}

func TestHealthIncludesVersion(t *testing.T) {
	app := newServer(filepath.Join(t.TempDir(), "default.jsonl"), t.TempDir())
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	response := httptest.NewRecorder()

	app.routes().ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status code = %d, body = %s", response.Code, response.Body.String())
	}

	var body map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode health response: %v", err)
	}
	if body["version"] != version {
		t.Fatalf("version = %v, want %q", body["version"], version)
	}
}

func TestValidateListenAddress(t *testing.T) {
	tests := []struct {
		address string
		wantErr bool
	}{
		{address: "127.0.0.1:19820"},
		{address: "[::1]:19820"},
		{address: "localhost:19820"},
		{address: "0.0.0.0:19820", wantErr: true},
		{address: ":19820", wantErr: true},
		{address: "invalid", wantErr: true},
	}

	for _, test := range tests {
		t.Run(test.address, func(t *testing.T) {
			err := validateListenAddress(test.address)
			if (err != nil) != test.wantErr {
				t.Fatalf("validateListenAddress() err = %v, wantErr = %t", err, test.wantErr)
			}
		})
	}
}

func postEntry(t *testing.T, handler http.Handler, requestBody appendRequest) *httptest.ResponseRecorder {
	t.Helper()

	body, err := json.Marshal(requestBody)
	if err != nil {
		t.Fatalf("encode request: %v", err)
	}
	request := httptest.NewRequest(http.MethodPost, "/v1/entries", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set(clientHeaderName, clientHeaderValue)

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}
