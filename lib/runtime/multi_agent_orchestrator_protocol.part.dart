part of 'multi_agent_orchestrator.dart';

typedef CliProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

/// 协作日志条目
class CollaborationLogEntry {
  const CollaborationLogEntry({
    required this.timestamp,
    required this.level,
    required this.emoji,
    required this.message,
  });

  final DateTime timestamp;
  final CollaborationLogLevel level;
  final String emoji;
  final String message;

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

enum CollaborationLogLevel { debug, info, warning, error, success }

/// CLI 执行结果
class CliResult {
  const CliResult({
    required this.output,
    required this.error,
    required this.exitCode,
  });

  final String output;
  final String error;
  final int exitCode;

  bool get success => exitCode == 0 && error.isEmpty;
}

/// Architect 执行结果
class ArchitectResult {
  ArchitectResult({
    required this.output,
    required this.decomposedTasks,
    required this.duration,
  });

  final String output;
  final List<SubTask> decomposedTasks;
  final Duration duration;
}

/// Engineer 执行结果
class EngineerResult {
  EngineerResult({
    required this.output,
    required this.codeOutput,
    required this.completedTasks,
    required this.duration,
  });

  final String output;
  String codeOutput;
  final List<SubTask> completedTasks;
  final Duration duration;
}

/// Tester 执行结果
class TesterResult {
  TesterResult({
    required this.output,
    required this.score,
    required this.feedback,
    required this.duration,
  });

  final String output;
  final int score;
  final String feedback;
  final Duration duration;
}

/// 协作步骤
class CollaborationStep {
  const CollaborationStep({
    required this.role,
    required this.status,
    required this.output,
    required this.duration,
    this.iteration,
    this.score,
  });

  final String role;
  final StepStatus status;
  final String output;
  final Duration duration;
  final int? iteration;
  final int? score;

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'status': status.name,
      'output': output,
      'durationMs': duration.inMilliseconds,
      if (iteration != null) 'iteration': iteration,
      if (score != null) 'score': score,
    };
  }
}

enum StepStatus { pending, running, completed, failed }

/// 子任务
class SubTask {
  const SubTask({
    required this.id,
    required this.description,
    required this.order,
    required this.type,
  });

  final String id;
  final String description;
  final int order;
  final SubTaskType type;
}

enum SubTaskType { design, implementation, testing, documentation, deployment }

/// 附件
class CollaborationAttachment {
  const CollaborationAttachment({
    required this.name,
    required this.description,
    required this.path,
  });

  final String name;
  final String description;
  final String path;
}

/// 协作最终结果
class CollaborationResult {
  const CollaborationResult({
    required this.success,
    required this.steps,
    required this.finalCode,
    required this.finalScore,
    required this.duration,
    required this.iterations,
    this.error,
  });

  final bool success;
  final List<CollaborationStep> steps;
  final String finalCode;
  final int finalScore;
  final Duration duration;
  final int iterations;
  final String? error;

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'steps': steps.map((item) => item.toJson()).toList(growable: false),
      'finalCode': finalCode,
      'finalScore': finalScore,
      'durationMs': duration.inMilliseconds,
      'iterations': iterations,
      if (error != null) 'error': error,
    };
  }
}
