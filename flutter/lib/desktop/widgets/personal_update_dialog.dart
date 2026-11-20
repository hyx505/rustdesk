import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path/path.dart' as p;

import 'personal_update_feed.dart';

const _sourceOption = 'personal-remote-update-source';
const _profileFile = 'PersonalRemote.server.json';

void showPersonalUpdateDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PersonalUpdateDialog(),
  );
}

enum _UpdatePhase {
  idle,
  checking,
  available,
  downloading,
  downloaded,
  opening
}

class _PersonalUpdateDialog extends StatefulWidget {
  const _PersonalUpdateDialog();

  @override
  State<_PersonalUpdateDialog> createState() => _PersonalUpdateDialogState();
}

class _PersonalUpdateDialogState extends State<_PersonalUpdateDialog> {
  final _source =
      TextEditingController(text: bind.mainGetLocalOption(key: _sourceOption));
  _UpdatePhase _phase = _UpdatePhase.idle;
  PersonalUpdateFeed? _feed;
  PersonalUpdateRelease? _release;
  File? _installer;
  String? _message;
  bool _error = false;
  int _percentage = 0;

  bool get _busy => switch (_phase) {
        _UpdatePhase.checking ||
        _UpdatePhase.downloading ||
        _UpdatePhase.opening =>
          true,
        _ => false,
      };
  File get _profile =>
      File(p.join(p.dirname(Platform.resolvedExecutable), _profileFile));

  @override
  void dispose() {
    _source.dispose();
    _discardDownload();
    super.dispose();
  }

  Future<void> _deleteDownload(File file) async {
    try {
      await file.delete();
      await file.parent.delete();
    } on FileSystemException {
      // The system temporary directory can clean up files held open by Windows.
    }
  }

  void _discardDownload() {
    final file = _installer;
    _installer = null;
    if (file != null) unawaited(_deleteDownload(file));
  }

  void _clearResult() {
    _discardDownload();
    setState(() {
      _feed = null;
      _release = null;
      _phase = _UpdatePhase.idle;
      _message = null;
      _error = false;
    });
  }

  Future<void> _chooseFolder() async {
    final folder = await FilePicker.platform.getDirectoryPath();
    if (folder == null || !mounted || _busy) return;
    _source.text = folder;
    _clearResult();
  }

  void _fail(Object error, _UpdatePhase retryPhase) {
    if (!mounted) return;
    setState(() {
      _phase = retryPhase;
      _error = true;
      _message = switch (error) {
        FormatException() => error.message,
        FileSystemException() => '无法读取更新目录、安装包或本机配置，请检查路径和权限。',
        TimeoutException() => '连接更新源超时，请重试。',
        SocketException() ||
        HttpException() ||
        HandshakeException() =>
          '无法连接更新源，请检查网络和 HTTPS 证书。',
        ProcessException() => 'Windows 未能打开安装器。',
        _ => '更新失败，请检查更新源后重试。',
      };
    });
  }

  Future<void> _check() async {
    if (_busy) return;
    _clearResult();
    setState(() => _phase = _UpdatePhase.checking);
    try {
      final source = _source.text.trim();
      final feed = PersonalUpdateFeed.parse(source);
      final release = await feed.check();
      final newer = release.isNewerThan(personalRemoteVersion);
      if (newer) release.checkProfile(_profile);
      await bind.mainSetLocalOption(key: _sourceOption, value: source);
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _release = newer ? release : null;
        _phase = newer ? _UpdatePhase.available : _UpdatePhase.idle;
        _message = newer ? '发现新版 ${release.version}' : '当前版本已是更新源中的最新版。';
      });
    } catch (error) {
      _fail(error, _UpdatePhase.idle);
    }
  }

  Future<void> _download() async {
    final release = _release!;
    setState(() {
      _phase = _UpdatePhase.downloading;
      _percentage = 0;
      _message = null;
      _error = false;
    });
    try {
      final file = await _feed!.download(release, onProgress: (received) {
        final percentage = received * 100 ~/ release.size;
        if (mounted && percentage != _percentage) {
          setState(() => _percentage = percentage);
        }
      });
      if (!mounted) {
        await _deleteDownload(file);
        return;
      }
      setState(() {
        _installer = file;
        _phase = _UpdatePhase.downloaded;
        _message = '已验证 ${release.version} 安装包。结束正在进行的远控后，可打开安装器。';
      });
    } catch (error) {
      _fail(error, _UpdatePhase.available);
    }
  }

  Future<void> _install() async {
    final release = _release!;
    final installer = _installer!;
    final installDir = bind.installInstallPath();
    final actualDir = p.normalize(p.dirname(Platform.resolvedExecutable));
    if (!bind.mainIsInstalled() ||
        actualDir.toLowerCase() != p.normalize(installDir).toLowerCase()) {
      _fail(const FormatException('请从已安装的自用远控打开更新。'), _UpdatePhase.downloaded);
      return;
    }
    setState(() {
      _phase = _UpdatePhase.opening;
      _error = false;
    });
    try {
      release.checkProfile(_profile);
      await release.verifyFile(installer);
      if (!mounted) return;
      await Process.start(installer.path, const [],
          workingDirectory: installer.parent.path,
          mode: ProcessStartMode.detached);
      _installer = null;
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.idle;
        _message = '安装器已打开，请沿用原安装目录完成覆盖升级。';
      });
    } catch (error) {
      if (error is FormatException || error is FileSystemException) {
        _discardDownload();
        _fail(error, _UpdatePhase.available);
      } else {
        _fail(error, _UpdatePhase.downloaded);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('检查更新'),
        content: SizedBox(
          width: 450,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('当前版本 $personalRemoteVersion'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _source,
              enabled: !_busy,
              onChanged: (_) => _clearResult(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: '更新目录或 HTTPS 地址',
                suffixIcon: IconButton(
                  onPressed: _busy ? null : _chooseFolder,
                  tooltip: '选择更新目录',
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ),
            ),
            if (_phase == _UpdatePhase.checking ||
                _phase == _UpdatePhase.opening) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_phase == _UpdatePhase.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _percentage / 100),
              Text('$_percentage%'),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_message!,
                    style: _error
                        ? TextStyle(color: theme.colorScheme.error)
                        : null),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (_phase == _UpdatePhase.available)
            FilledButton(onPressed: _download, child: const Text('下载更新'))
          else if (_phase == _UpdatePhase.downloaded)
            FilledButton(onPressed: _install, child: const Text('打开安装器'))
          else
            FilledButton(
                onPressed: _busy ? null : _check, child: const Text('检查')),
        ],
      ),
    );
  }
}
