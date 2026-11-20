import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/native/win32.dart';

const personalOpenOnLogin = 'personal-remote-open-on-login';
const personalStartServiceOnOpen = 'personal-remote-start-service-on-open';

Future<void> startPersonalServiceOnOpen() async {
  if (Platform.environment['PERSONALREMOTE_SKIP_SERVICE_AUTOSTART'] == '1' ||
      bind.isDisableSettings() ||
      isOptionFixed(kOptionStopService) ||
      bind.mainGetLocalOption(key: personalStartServiceOnOpen) != 'Y') {
    return;
  }
  try {
    final installed = bind.mainIsInstalled();
    if (!installed) {
      if (await mainGetBoolOption(kOptionStopService)) {
        await start_service(true);
      }
      return;
    }

    final status = personalWindowsServiceStatus();
    if (status == PersonalWindowsServiceStatus.missing) {
      // The app's existing Stop action removes the Windows service.
      // Use its usual service installation flow to restore it.
      await start_service(true);
    } else if (status == PersonalWindowsServiceStatus.stopped) {
      startExistingPersonalWindowsService();
    } else {
      return;
    }

    for (var attempt = 0; attempt < 12; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final current = personalWindowsServiceStatus();
      if (current == PersonalWindowsServiceStatus.active) return;
    }
    showToast('远控服务尚未启动，可在设置中检查状态。');
  } catch (error) {
    debugPrint('PersonalRemote could not start its Windows service: $error');
    showToast('未能自动启动远控服务，请在设置中手动启动。');
  }
}
