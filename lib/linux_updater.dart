import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// The updater runs only on explicit desktop menu requests. Android stays offline.
class LinuxRelease {
  LinuxRelease(this.tag) {
    if (!RegExp(r'^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$').hasMatch(tag)) {
      throw const FormatException('Invalid release version');
    }
  }
  final String tag;
  bool newerThan(String installed) {
    final left = tag.substring(1).split('.').map(int.parse).toList();
    final right = LinuxRelease(
      installed,
    ).tag.substring(1).split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (left[i] != right[i]) return left[i] > right[i];
    }
    return false;
  }
}

typedef UpdateCommand = Future<ProcessResult> Function(List<String> arguments);

class LinuxUpdater {
  LinuxUpdater({UpdateCommand? command, String? installedTag})
    : _command = command ?? _runBundled,
      _installedTag = installedTag;
  final UpdateCommand _command;
  final String? _installedTag;
  static bool get supported => Platform.isLinux;

  String? get installedTag {
    if (_installedTag != null) return _installedTag;
    try {
      final file = File(
        '${File(Platform.resolvedExecutable).parent.path}/release-version.txt',
      );
      return LinuxRelease(file.readAsStringSync().trim()).tag;
    } on Object {
      return null;
    }
  }

  static Future<ProcessResult> _runBundled(List<String> arguments) async {
    if (!supported) throw UnsupportedError('Updates are available on Linux.');
    final script = File(
      '${File(Platform.resolvedExecutable).parent.path}/update-spritedawg.sh',
    );
    if (!await script.exists()) {
      throw StateError(
        'The updater is available in official Linux AppImages.',
      );
    }
    final appimage = Platform.environment['APPIMAGE'];
    final current = File(
      '${script.parent.path}/release-version.txt',
    ).readAsStringSync().trim();
    // APPIMAGE is supplied by the runtime and points outside its read-only mount.
    // Extracted AppDirs have no replaceable AppImage; use the installer once.
    if (!arguments.contains('--check') && appimage == null) {
      throw StateError(
        'Open the AppImage itself to update it, or run install-spritedawg.sh once.',
      );
    }
    final process = await Process.start('/bin/bash', [
      script.path,
      ...arguments,
      if (appimage != null) ...[
        '--appimage',
        appimage,
        '--current-version',
        current,
      ],
    ]);
    var length = 0;
    final output = StringBuffer(), errors = StringBuffer();
    void collect(StringBuffer buffer, String text) {
      length += text.length;
      if (length > 65536) {
        process.kill(ProcessSignal.sigkill);
      } else {
        buffer.write(text);
      }
    }

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .listen((text) => collect(output, text))
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen((text) => collect(errors, text))
        .asFuture<void>();
    try {
      final code = await process.exitCode.timeout(const Duration(minutes: 10));
      await Future.wait([stdoutDone, stderrDone]);
      if (length > 65536) throw StateError('Unexpected updater output.');
      return ProcessResult(
        process.pid,
        code,
        output.toString(),
        errors.toString(),
      );
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      throw StateError(
        'Update timed out. Check the installed version before retrying.',
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(List<String> arguments) async {
    final result = await _command(arguments);
    if (result.exitCode != 0) {
      final error = result.stderr.toString().trim();
      throw StateError(
        error.isEmpty ? 'Update failed. Try again later.' : error,
      );
    }
    final value = jsonDecode(result.stdout.toString());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid updater response');
    }
    return value;
  }

  Future<LinuxRelease> check() async {
    final data = await _invoke(['--check']);
    if (data['tag'] is! String || !['x64', 'arm64'].contains(data['arch'])) {
      throw const FormatException('Invalid release metadata');
    }
    return LinuxRelease(data['tag'] as String);
  }

  Future<void> install(LinuxRelease release) async {
    final data = await _invoke(['--version', release.tag]);
    if (data['tag'] != release.tag) {
      throw const FormatException('Installed version did not match');
    }
  }
}

Future<void> showLinuxUpdater(BuildContext context, {LinuxUpdater? updater}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UpdateDialog(updater: updater ?? LinuxUpdater()),
    );

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.updater});
  final LinuxUpdater updater;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool busy = true, installed = false;
  LinuxRelease? release;
  String? error;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final result = await widget.updater.check();
      if (mounted) setState(() => release = result);
    } on Object catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _install() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.updater.install(release!);
      if (mounted) setState(() => installed = true);
    } on Object catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.updater.installedTag;
    final available =
        release != null && (current == null || release!.newerThan(current));
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('SpriteDawg updates'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (busy) const LinearProgressIndicator(),
              if (busy) const SizedBox(height: 12),
              Text(
                error ??
                    (installed
                        ? '${release!.tag} replaced this AppImage. Save your work, then close and reopen it when ready; your open drawings are unchanged.'
                        : busy
                        ? (release == null
                              ? 'Checking GitHub…'
                              : 'Installing ${release!.tag}…')
                        : available
                        ? '${release!.tag} is available. Install for this user?'
                        : 'You’re up to date${current == null ? '' : ' ($current)'}.'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(installed ? 'Done' : 'Close'),
          ),
          if (!installed && available && error == null)
            FilledButton(
              onPressed: busy ? null : _install,
              child: const Text('Install update'),
            ),
        ],
      ),
    );
  }
}
