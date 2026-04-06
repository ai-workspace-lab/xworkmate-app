import 'package:xworkmate/runtime/runtime_models.dart';

TaskThread buildTaskThreadFixture({
  required String threadId,
  String title = '',
  double createdAtMs = 0,
  double? updatedAtMs,
  ThreadOwnerScope? ownerScope,
  AssistantExecutionTarget executionTarget =
      AssistantExecutionTarget.singleAgent,
  SingleAgentProvider singleAgentProvider = SingleAgentProvider.auto,
  String workspacePath = '/tmp/task-thread-fixture',
  WorkspaceKind workspaceKind = WorkspaceKind.localFs,
  bool writable = true,
  String? displayPath,
  List<GatewayChatMessage> messages = const <GatewayChatMessage>[],
  String assistantModelId = '',
  List<AssistantThreadSkillEntry> importedSkills =
      const <AssistantThreadSkillEntry>[],
  List<String> selectedSkillKeys = const <String>[],
  AssistantPermissionLevel permissionLevel =
      AssistantPermissionLevel.defaultAccess,
  AssistantMessageViewMode messageViewMode =
      AssistantMessageViewMode.rendered,
  String? gatewayEntryState,
  bool archived = false,
  String? lifecycleStatus,
  double? lastRunAtMs,
  String? lastResultCode,
}) {
  final normalizedDisplayPath = displayPath ?? workspacePath;
  final normalizedStatus = lifecycleStatus ?? 'ready';
  return TaskThread(
    threadId: threadId,
    title: title,
    ownerScope:
        ownerScope ??
        const ThreadOwnerScope(
          realm: ThreadRealm.local,
          subjectType: ThreadSubjectType.user,
          subjectId: '',
          displayName: '',
        ),
    workspaceBinding: WorkspaceBinding(
      workspaceId: threadId,
      workspaceKind: workspaceKind,
      workspacePath: workspacePath,
      displayPath: normalizedDisplayPath,
      writable: writable,
    ),
    executionBinding: ExecutionBinding(
      executionMode: switch (executionTarget) {
        AssistantExecutionTarget.singleAgent => ThreadExecutionMode.localAgent,
        AssistantExecutionTarget.local => ThreadExecutionMode.gatewayLocal,
        AssistantExecutionTarget.remote => ThreadExecutionMode.gatewayRemote,
      },
      executorId: singleAgentProvider.providerId,
      providerId: singleAgentProvider.providerId,
      endpointId: '',
    ),
    contextState: ThreadContextState(
      messages: messages,
      selectedModelId: assistantModelId,
      selectedSkillKeys: selectedSkillKeys,
      importedSkills: importedSkills,
      permissionLevel: permissionLevel,
      messageViewMode: messageViewMode,
      latestResolvedRuntimeModel: '',
      gatewayEntryState: gatewayEntryState,
    ),
    lifecycleState: ThreadLifecycleState(
      archived: archived,
      status: normalizedStatus,
      lastRunAtMs: lastRunAtMs,
      lastResultCode: lastResultCode,
    ),
    createdAtMs: createdAtMs,
    updatedAtMs: updatedAtMs,
  );
}
