import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_hbb/desktop/widgets/personal_update_feed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const version = '0.1.10';
  const filename = 'PersonalRemote-$version-windows-x64.exe';
  final bytes = utf8.encode('PersonalRemote installer test data');
  final profile = {
    'id_server': 'private.example',
    'relay_server': '',
    'server_key': 'key'
  };
  final profileHash =
      sha256.convert(utf8.encode(profile.values.join('\u0000')));

  late Directory directory;
  late File manifest;
  late File package;
  late File config;
  Map<String, dynamic> manifestData() => {
        'schema': 1,
        'version': version,
        'file': filename,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'profile_sha256': profileHash.toString(),
      };

  setUp(() {
    directory = Directory.systemTemp.createTempSync('personal-update-test-');
    manifest = File(p.join(directory.path, personalUpdateManifest));
    package = File(p.join(directory.path, filename));
    config = File(p.join(directory.path, 'PersonalRemote.server.json'));
    manifest.writeAsStringSync(jsonEncode(manifestData()));
    package.writeAsBytesSync(bytes);
    config.writeAsStringSync(jsonEncode(profile));
  });

  tearDown(() {
    manifest.deleteSync();
    package.deleteSync();
    config.deleteSync();
    directory.deleteSync();
  });

  test(
      'compares personal version parts numerically and rejects redirects in names',
      () async {
    final source = PersonalUpdateFeed.parse(directory.path);
    final release = await source.check();
    expect(release.isNewerThan('0.1.6'), isTrue);
    expect(release.isNewerThan(version), isFalse);
    expect(release.isNewerThan('0.2.0'), isFalse);
    manifest.writeAsStringSync(
        jsonEncode(manifestData()..['file'] = '../update.exe'));
    await expectLater(source.check(), throwsFormatException);
    expect(() => PersonalUpdateFeed.parse('http://private.example'),
        throwsFormatException);
  });

  test('accepts the configured server profile and detects a mismatching one',
      () async {
    final release = await PersonalUpdateFeed.parse(directory.path).check();
    expect(() => release.checkProfile(config), returnsNormally);
    config.writeAsStringSync(
        jsonEncode({...profile, 'id_server': 'different.example'}));
    expect(() => release.checkProfile(config), throwsFormatException);
  });

  test('copies and verifies a package before download succeeds', () async {
    final source = PersonalUpdateFeed.parse(directory.path);
    final release = await source.check();
    var received = 0;
    final staged =
        await source.download(release, onProgress: (n) => received = n);
    addTearDown(() async {
      await staged.delete();
      await staged.parent.delete();
    });
    expect(received, bytes.length);
    expect(await staged.readAsBytes(), orderedEquals(bytes));
    package.writeAsBytesSync([...bytes.take(bytes.length - 1), 0]);
    await expectLater(
        source.download(release, onProgress: (_) {}), throwsFormatException);
  });
}
