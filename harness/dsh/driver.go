package dsh

import "github.com/discobox-ai/discobox/harness"

type Driver struct{}

func (Driver) ID() string { return "dsh" }

func (Driver) Definition() harness.Definition {
	return harness.Definition{
		ID: "dsh", Name: "DeepSeek Harness", Description: "DeepSeek Harness browser UI configured for CLI Proxy API.",
		Image: harness.ImageRef("discobox-harness-dsh"), Configure: &harness.Configure{},
	}
}
