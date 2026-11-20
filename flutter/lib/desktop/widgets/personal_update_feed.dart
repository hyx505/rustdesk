import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const personalRemoteVersion = '0.1.6';
const personalUpdateManifest = 'update.json';
const _maxManifestBytes = 32 * 1024;
const _maxInstallerBytes = 256 * 1024 * 1024;
const _networkTimeout = Duration(seconds: 20);
final _versionPattern =
    RegExp(r'^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})$');
final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

List<int> _versionParts(String value) {
  if (!_versionPattern.hasMatch(value)) {
    throw const FormatException('更新清单中的版本号无效。');
  }
  return value.split('.').map(int.parse).toList();
}

class PersonalUpdateRelease {
  const PersonalUpdateRelease._(
      this.version, this.size, this.checksum, this.profileChecksum);

  factory PersonalUpdateRelease.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final size = json['size'];
    final checksum = json['sha256'];
    final profileChecksum = json['profile_sha256'];
    if (json['schema'] != 1 ||
        version is! String ||
        !_versionPattern.hasMatch(version) ||
        json['file'] != 'PersonalRemote-$version-windows-x64.exe' ||
        size is! int ||
        size <= 0 ||
        size > _maxInstallerBytes ||
        checksum is! String ||
        !_sha256Pattern.hasMatch(checksum) ||
        profileChecksum is! String ||
        !_sha256Pattern.hasMatch(profileChecksum)) {
      throw const FormatException('更新清单中的安装包信息无效。');
    }
    return PersonalUpdateRelease._(version, size, checksum, profileChecksum);
  }

  final String version;
  final int size;
  final String checksum;
  final String profileChecksum;

  String get fileName => 'PersonalRemote-$version-windows-x64.exe';

  bool isNewerThan(String current) {
    final candidate = _versionParts(version);
    final installed = _versionParts(current);
    for (var i = 0; i < candidate.length; i++) {
      if (candidate[i] != installed[i]) return candidate[i] > installed[i];
    }
    return false;
  }

  void checkProfile(File profile) {
    final data = jsonDecode(profile.readAsStringSync());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('无法读取当前客户端的服务器配置。');
    }
    final id = data['id_server'];
    final relay = data['relay_server'] ?? '';
    final key = data['server_key'];
    if (id is! String || relay is! String || key is! String) {
      throw const FormatException('无法读取当前客户端的服务器配置。');
    }
    final fingerprint =
        sha256.convert(utf8.encode([id, relay, key].join('\u0000')));
    if (fingerprint.toString() != profileChecksum) {
      throw const FormatException('新版安装包的服务器配置和当前客户端不同。');
    }
  }

  Future<void> verifyFile(File installer) async {
    if (await installer.length() != size ||
        (await sha256.bind(installer.openRead()).single).toString() !=
            checksum) {
      throw const FormatException('安装包校验失败，请检查更新源后重试。');
    }
  }
}

class PersonalUpdateFeed {
  PersonalUpdateFeed._(this._directory, this._manifest);

  factory PersonalUpdateFeed.parse(String input) {
    final source = input.trim();
    if (p.isAbsolute(source))
      return PersonalUpdateFeed._(Directory(source), null);
    final uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请选择本地或共享目录，或输入 HTTPS 更新地址。');
    }
    final manifest = uri.path.endsWith('/$personalUpdateManifest')
        ? uri
        : uri.replace(
            path:
                '${uri.path.endsWith('/') ? uri.path : '${uri.path}/'}$personalUpdateManifest');
    return PersonalUpdateFeed._(null, manifest);
  }

  final Directory? _directory;
  final Uri? _manifest;

  Stream<List<int>> _read(String name) async* {
    final directory = _directory;
    if (directory != null) {
      yield* File(p.join(directory.path, name))
          .openRead()
          .timeout(_networkTimeout);
      return;
    }
    final manifest = _manifest!;
    final uri =
        name == personalUpdateManifest ? manifest : manifest.resolve(name);
    final client = HttpClient()..connectionTimeout = _networkTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_networkTimeout);
      request.followRedirects = false;
      final response = await request.close().timeout(_networkTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException('更新源返回 HTTP ${response.statusCode}。');
      }
      yield* response.timeout(_networkTimeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<PersonalUpdateRelease> check() async {
    final bytes = <int>[];
    await for (final chunk in _read(personalUpdateManifest)) {
      if (bytes.length + chunk.length > _maxManifestBytes) {
        throw const FormatException('更新清单过大。');
      }
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('更新清单格式有误。');
    }
    return PersonalUpdateRelease.fromJson(data);
  }

  Future<File> download(PersonalUpdateRelease release,
      {required void Function(int received) onProgress}) async {
    final scratch =
        await Directory.systemTemp.createTemp('personalremote-update-');
    final target = File(p.join(scratch.path, release.fileName));
    try {
      final output = await target.open(mode: FileMode.writeOnly);
      try {
        var received = 0;
        await for (final chunk in _read(release.fileName)) {
          received += chunk.length;
          if (received > release.size) {
            throw const FormatException('下载的文件大于更新清单所列的大小。');
          }
          await output.writeFrom(chunk);
          onProgress(received);
        }
      } finally {
        await output.close();
      }
      await release.verifyFile(target);
      return target;
    } catch (_) {
      if (await target.exists()) await target.delete();
      await scratch.delete();
      rethrow;
    }
  }
}
