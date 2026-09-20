// Package configuretest exercises configure scripts against a fake CLI Proxy API.
package configuretest

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/discobox-ai/discobox/harness"
)

// Output is the subset of the configure contract needed by harness tests.
type Output struct {
	Secrets []struct {
		EnvName     string `json:"envName"`
		Host        string `json:"host"`
		UsePrevious bool   `json:"usePrevious"`
	} `json:"secrets"`
	Files []struct {
		Path     string `json:"path"`
		Content  string `json:"content"`
		Template bool   `json:"template"`
	} `json:"files"`
}

// RunProxyConfigure runs the current directory's configure.sh with reusable
// sentinels and a deterministic two-model API response.
func RunProxyConfigure(t *testing.T) Output {
	t.Helper()
	raw, err := os.ReadFile("configure.sh")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	output := filepath.Join(dir, "output.json")
	script := strings.Replace(string(raw), "OUTPUT="+harness.ConfigureOutputPath, "OUTPUT="+output, 1)
	scriptPath := filepath.Join(dir, "configure.sh")
	if err := os.WriteFile(scriptPath, []byte(script), 0o600); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "bin")
	if err := os.Mkdir(bin, 0o700); err != nil {
		t.Fatal(err)
	}
	curl := filepath.Join(bin, "curl")
	if err := os.WriteFile(curl, []byte("#!/bin/sh\nprintf '%s\\n' '{\"data\":[{\"id\":\"model-z\"},{\"slug\":\"model-a\"}]}'\n"), 0o700); err != nil { //nolint:gosec // The fake curl must be executable from PATH.
		t.Fatal(err)
	}
	cmd := exec.CommandContext(t.Context(), "sh", scriptPath)
	cmd.Stdin = strings.NewReader("\n\n\n\n")
	cmd.Env = append(os.Environ(),
		"PATH="+bin+string(os.PathListSeparator)+os.Getenv("PATH"),
		"PREV_CLI_PROXY_API_KEY=prev-api",
		"PREV_CF_ACCESS_CLIENT_ID=prev-client-id",
		"PREV_CF_ACCESS_CLIENT_SECRET=prev-client-secret",
	)
	if combined, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("configure.sh: %v\n%s", err, combined)
	}
	encoded, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	var got Output
	if err := json.Unmarshal(encoded, &got); err != nil {
		t.Fatalf("configure output: %v\n%s", err, encoded)
	}
	return got
}
