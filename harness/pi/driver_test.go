package pi

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
	if def.ID != "pi" || def.Configure == nil {
		t.Fatalf("definition = %#v, want configurable pi", def)
	}
	raw, err := os.ReadFile("image.json")
	if err != nil {
		t.Fatal(err)
	}
	var image struct {
		Harness struct {
			ID      string           `json:"id"`
			Secrets []harness.Secret `json:"secrets"`
			Config  struct {
				Command []string `json:"command"`
			} `json:"config"`
		} `json:"harness"`
	}
	if err := json.Unmarshal(raw, &image); err != nil {
		t.Fatal(err)
	}
	if image.Harness.ID != def.ID || len(image.Harness.Secrets) != 3 {
		t.Fatalf("image harness = %#v", image.Harness)
	}
	for _, secret := range image.Harness.Secrets {
		if !secret.Required {
			t.Errorf("secret %s is optional", secret.Name)
		}
	}
	script, err := os.ReadFile("configure.sh")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{harness.ConfigureOutputPath, "host:$host", "usePrevious:true", "CF-Access-Client-Id", "CF-Access-Client-Secret"} {
		if !strings.Contains(string(script), want) {
			t.Errorf("configure script missing %q", want)
		}
	}
}

func TestLaunchJoinsPromptAndResumes(t *testing.T) {
	if got, want := launchertest.RunLauncher(t, "pi", []string{"fix", "the", "tests"}), []string{"fix the tests"}; !slices.Equal(got, want) {
		t.Fatalf("pi argv = %#v, want %#v", got, want)
	}
	if got, want := launchertest.RunLauncher(t, "pi", []string{harness.ResumeFlag, "ignored"}), []string{"--continue"}; !slices.Equal(got, want) {
		t.Fatalf("resumed pi argv = %#v, want %#v", got, want)
	}
}

func TestPromptIsolatesToolFreeCalls(t *testing.T) {
	raw, err := os.ReadFile("prompt.sh")
	if err != nil {
		t.Fatal(err)
	}
	script := string(raw)
	for _, want := range []string{"--no-session", "--no-tools", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-context-files", "--no-approve"} {
		if !strings.Contains(script, want) {
			t.Errorf("prompt wrapper missing %s", want)
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
	var models string
	for _, file := range out.Files {
		if file.Path == ".pi/agent/models.json" {
			models = file.Content
		}
		if strings.Contains(file.Content, "prev-") {
			t.Errorf("file %s contains a credential", file.Path)
		}
	}
	for _, want := range []string{"model-a", "model-z", "$CLI_PROXY_API_KEY", "$CF_ACCESS_CLIENT_ID", "$CF_ACCESS_CLIENT_SECRET"} {
		if !strings.Contains(models, want) {
			t.Errorf("models.json missing %q: %s", want, models)
		}
	}
}
