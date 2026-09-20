package dsh

import (
	"encoding/json"
	"os"
	"slices"
	"strings"
	"testing"

	"github.com/discobox-ai/discobox/harness"
	"github.com/discobox-ai/discobox/harness/internal/configuretest"
	"github.com/discobox-ai/discobox/harness/internal/launchertest"
)

func TestDefinitionAndImageContract(t *testing.T) {
	def := Driver{}.Definition()
	if def.ID != "dsh" || def.Configure == nil {
		t.Fatalf("definition = %#v, want configurable dsh", def)
	}
	raw, err := os.ReadFile("image.json")
	if err != nil {
		t.Fatal(err)
	}
	var image struct {
		Env     map[string]string `json:"env"`
		Harness struct {
			ID      string           `json:"id"`
			Secrets []harness.Secret `json:"secrets"`
		} `json:"harness"`
	}
	if err := json.Unmarshal(raw, &image); err != nil {
		t.Fatal(err)
	}
	if image.Harness.ID != def.ID || len(image.Harness.Secrets) != 3 || image.Env["DSH_TELEMETRY_MODE"] != "DISABLED" {
		t.Fatalf("image contract = %#v env=%v", image.Harness, image.Env)
	}
	script, err := os.ReadFile("configure.sh")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{harness.ConfigureOutputPath, "host:$host", "usePrevious:true", "apiKeyEnv: CLI_PROXY_API_KEY", "session-log-deepseek", "template:true"} {
		if !strings.Contains(string(script), want) {
			t.Errorf("configure script missing %q", want)
		}
	}
}

func TestLaunchStartsBrowserHarness(t *testing.T) {
	got := launchertest.RunLauncher(t, "dsh", []string{harness.ResumeFlag})
	want := []string{"web", "--host", "127.0.0.1", "--port", "3080", "--no-open"}
	if !slices.Equal(got, want) {
		t.Fatalf("dsh argv = %#v, want %#v", got, want)
	}
}

func TestPromptUsesHeadlessProfileAndRoleOverlay(t *testing.T) {
	raw, err := os.ReadFile("prompt.sh")
	if err != nil {
		t.Fatal(err)
	}
	script := string(raw)
	for _, want := range []string{"--profile headless", "--patch", "agent-default-model", "judgeModel", "fastModel", "tool-bash", "disabled: true"} {
		if !strings.Contains(script, want) {
			t.Errorf("prompt wrapper missing %q", want)
		}
	}
}

func TestConfigureDiscoversModelsWithoutPersistingCredentials(t *testing.T) {
	out := configuretest.RunProxyConfigure(t)
	if len(out.Secrets) != 3 {
		t.Fatalf("secrets = %#v, want three", out.Secrets)
	}
	for _, secret := range out.Secrets {
		if !secret.UsePrevious || secret.Host != "cli-proxy.jimboylabs.biz.id" {
			t.Errorf("secret = %#v, want host-scoped reuse", secret)
		}
	}
	var patch string
	for _, file := range out.Files {
		if file.Path == ".dsh/cordis.patch.yml" {
			patch = file.Content
		}
		if strings.Contains(file.Content, "prev-") {
			t.Errorf("file %s contains a credential", file.Path)
		}
	}
	for _, want := range []string{"model-a", "model-z", "apiKeyEnv: CLI_PROXY_API_KEY", "{{ .secrets.CF_ACCESS_CLIENT_ID }}", "{{ .secrets.CF_ACCESS_CLIENT_SECRET }}"} {
		if !strings.Contains(patch, want) {
			t.Errorf("cordis.patch.yml missing %q: %s", want, patch)
		}
	}
}
