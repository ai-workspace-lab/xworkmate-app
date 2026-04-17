import os

path = '/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/internal/acp/server.go'
with open(path, 'r') as f:
    content = f.read()

content = content.replace(
    'switch method {\n\tcase "acp.capabilities":',
    'switch method {\n\tcase "health":\n\t\treturn map[string]any{"status": "ok", "version": "0.7.0"}, nil\n\tcase "acp.capabilities":'
)

content = content.replace(
    'apiKey := strings.TrimSpace(shared.StringArg(params, "aiGatewayApiKey", ""))',
    'apiKey := strings.TrimSpace(shared.StringArg(params, "aiGatewayApiKey", os.Getenv("AI_GATEWAY_API_KEY")))'
)
content = content.replace(
    'baseURL := shared.NormalizeBaseURL(\n\t\tshared.StringArg(params, "aiGatewayBaseUrl", ""),\n\t)',
    'baseURL := shared.NormalizeBaseURL(\n\t\tshared.StringArg(params, "aiGatewayBaseUrl", os.Getenv("AI_GATEWAY_BASE_URL")),\n\t)'
)

content = content.replace(
    'session.history = append(session.history, prompt)',
    'session.history = append(session.history, "USER: " + prompt)'
)

target_single = '''\t\tresult := s.runSingleAgent(
\t\t\tctx,
\t\t\tsession,
\t\t\texecutionParams,
\t\t\tturnID,
\t\t\tnotify,
\t\t)
\t\treturn result.response, result.err
\t}'''

replace_single = '''\t\tresult := s.runSingleAgent(
\t\t\tctx,
\t\t\tsession,
\t\t\texecutionParams,
\t\t\tturnID,
\t\t\tnotify,
\t\t)
\t\tif result.err == nil {
\t\t\toutput := strings.TrimSpace(fmt.Sprint(result.response["output"]))
\t\t\tif output != "" {
\t\t\t\tsession.history = append(session.history, "ASSISTANT: " + output)
\t\t\t}
\t\t}
\t\treturn result.response, result.err
\t}'''

content = content.replace(target_single, replace_single)

target_multi = '''\t\tresult := s.runMultiAgent(
\t\t\tctx,
\t\t\tsession,
\t\t\texecutionParams,
\t\t\tturnID,
\t\t\tnotify,
\t\t)
\t\treturn result.response, result.err
\t}'''

replace_multi = '''\t\tresult := s.runMultiAgent(
\t\t\tctx,
\t\t\tsession,
\t\t\texecutionParams,
\t\t\tturnID,
\t\t\tnotify,
\t\t)
\t\tif result.err == nil {
\t\t\tsummary := strings.TrimSpace(fmt.Sprint(result.response["summary"]))
\t\t\tif summary != "" {
\t\t\t\tsession.history = append(session.history, "ASSISTANT: " + summary)
\t\t\t}
\t\t}
\t\treturn result.response, result.err
\t}'''

content = content.replace(target_multi, replace_multi)

with open(path, 'w') as f:
    f.write(content)
