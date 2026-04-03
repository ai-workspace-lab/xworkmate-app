package router

import (
	"testing"

	"xworkmate/go_core/internal/memory"
	"xworkmate/go_core/internal/skills"
)

func TestResolveExplicitTargetOverridesAuto(t *testing.T) {
	resolver := Resolver{
		SkillFinder:   skills.StaticFinder{},
		MemoryService: memory.Service{},
	}

	result := resolver.Resolve(Request{
		Prompt:                  "search the web and summarize results",
		RoutingMode:             RoutingModeExplicit,
		ExplicitExecutionTarget: "singleAgent",
		ExplicitProviderID:      "codex",
		ExplicitModel:           "gpt-5.4",
	})

	if result.ResolvedExecutionTarget != ExecutionTargetSingleAgent {
		t.Fatalf("expected explicit single-agent route, got %#v", result)
	}
	if result.ResolvedEndpointTarget != EndpointTargetSingleAgent {
		t.Fatalf("expected singleAgent endpoint target, got %#v", result)
	}
	if result.ResolvedProviderID != "codex" || result.ResolvedModel != "gpt-5.4" {
		t.Fatalf("unexpected explicit provider/model: %#v", result)
	}
}

func TestResolveAutoLocalTaskToSingleAgent(t *testing.T) {
	resolver := Resolver{
		SkillFinder:   skills.StaticFinder{},
		MemoryService: memory.Service{},
	}

	result := resolver.Resolve(Request{
		Prompt: "create a PowerPoint deck from this outline",
	})

	if result.ResolvedExecutionTarget != ExecutionTargetSingleAgent {
		t.Fatalf("expected single-agent route, got %#v", result)
	}
}

func TestResolveAutoOnlineTaskToGateway(t *testing.T) {
	resolver := Resolver{
		SkillFinder:   skills.StaticFinder{},
		MemoryService: memory.Service{},
	}

	result := resolver.Resolve(Request{
		Prompt:                 "跨浏览器执行并搜索最新资讯",
		PreferredGatewayTarget: EndpointTargetLocal,
	})

	if result.ResolvedExecutionTarget != ExecutionTargetGateway {
		t.Fatalf("expected gateway route, got %#v", result)
	}
	if result.ResolvedEndpointTarget != EndpointTargetLocal {
		t.Fatalf("expected local gateway target, got %#v", result)
	}
}

func TestResolveComplexTaskUpgradesToMultiAgent(t *testing.T) {
	resolver := Resolver{
		SkillFinder:   skills.StaticFinder{},
		MemoryService: memory.Service{},
	}

	result := resolver.Resolve(Request{
		Prompt: "analyze these files, review the output, and summarize multiple deliverables",
	})

	if result.ResolvedExecutionTarget != ExecutionTargetMultiAgent {
		t.Fatalf("expected multi-agent route, got %#v", result)
	}
}
