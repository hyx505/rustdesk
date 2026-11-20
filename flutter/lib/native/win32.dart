import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';

import 'package:win32/win32.dart' as win32;

/// Get windows target build number.
///
/// [Note]
/// Please use this function wrapped with `Platform.isWindows`.
int getWindowsTargetBuildNumber_() {
  final rtlGetVersion = DynamicLibrary.open('ntdll.dll').lookupFunction<
      Void Function(Pointer<win32.OSVERSIONINFOEX>),
      void Function(Pointer<win32.OSVERSIONINFOEX>)>('RtlGetVersion');
  final osVersionInfo = _getOSVERSIONINFOEXPointer();
  rtlGetVersion(osVersionInfo);
  int buildNumber = osVersionInfo.ref.dwBuildNumber;
  calloc.free(osVersionInfo);
  return buildNumber;
}

/// Get Windows OS version pointer
///
/// [Note]
/// Please use this function wrapped with `Platform.isWindows`.
Pointer<win32.OSVERSIONINFOEX> _getOSVERSIONINFOEXPointer() {
  final pointer = calloc<win32.OSVERSIONINFOEX>();
  pointer.ref
    ..dwOSVersionInfoSize = sizeOf<win32.OSVERSIONINFOEX>()
    ..dwBuildNumber = 0
    ..dwMajorVersion = 0
    ..dwMinorVersion = 0
    ..dwPlatformId = 0
    ..szCSDVersion = ''
    ..wServicePackMajor = 0
    ..wServicePackMinor = 0
    ..wSuiteMask = 0
    ..wProductType = 0
    ..wReserved = 0;
  return pointer;
}

enum PersonalWindowsServiceStatus { missing, stopped, active }

const _personalServiceName = 'PersonalRemote';

PersonalWindowsServiceStatus personalWindowsServiceStatus() {
  int state = win32.SERVICE_STATUS_CURRENT_STATE.SERVICE_STOPPED;
  final result =
      _withPersonalWindowsService(win32.SERVICE_QUERY_STATUS, (service, arena) {
    final status = arena<win32.SERVICE_STATUS>();
    if (win32.QueryServiceStatus(service, status) == 0)
      return win32.GetLastError();
    state = status.ref.dwCurrentState;
    return 0;
  });
  if (result == win32.WIN32_ERROR.ERROR_SERVICE_DOES_NOT_EXIST) {
    return PersonalWindowsServiceStatus.missing;
  }
  if (result != 0)
    throw win32.WindowsException(win32.HRESULT_FROM_WIN32(result));
  return state == win32.SERVICE_STATUS_CURRENT_STATE.SERVICE_STOPPED
      ? PersonalWindowsServiceStatus.stopped
      : PersonalWindowsServiceStatus.active;
}

int _withPersonalWindowsService(
    int access, int Function(int service, Allocator allocator) use) {
  final manager =
      win32.OpenSCManager(nullptr, nullptr, win32.SC_MANAGER_CONNECT);
  if (manager == 0) return win32.GetLastError();
  return using((arena) {
    try {
      final name = _personalServiceName.toNativeUtf16(allocator: arena);
      final service = win32.OpenService(manager, name, access);
      if (service == 0) return win32.GetLastError();
      try {
        return use(service, arena);
      } finally {
        win32.CloseServiceHandle(service);
      }
    } finally {
      win32.CloseServiceHandle(manager);
    }
  });
}

void startExistingPersonalWindowsService() {
  final result = _withPersonalWindowsService(win32.SERVICE_START, (service, _) {
    return win32.StartService(service, 0, nullptr) == 0
        ? win32.GetLastError()
        : 0;
  });
  if (result == 0 ||
      result == win32.WIN32_ERROR.ERROR_SERVICE_ALREADY_RUNNING) {
    return;
  }
  if (result != win32.WIN32_ERROR.ERROR_ACCESS_DENIED) {
    throw win32.WindowsException(win32.HRESULT_FROM_WIN32(result));
  }
  // Use Windows' administrator consent when the user cannot start services.
  // Resolve the system tool explicitly, independent of the current directory.
  using((arena) {
    final directory = arena<Uint16>(win32.MAX_PATH).cast<Utf16>();
    final length = win32.GetSystemDirectory(directory, win32.MAX_PATH);
    if (length == 0 || length >= win32.MAX_PATH) {
      throw StateError('Could not find the Windows system directory.');
    }
    final tool =
        '${directory.toDartString()}\\sc.exe'.toNativeUtf16(allocator: arena);
    final operation = 'runas'.toNativeUtf16(allocator: arena);
    final arguments =
        'start $_personalServiceName'.toNativeUtf16(allocator: arena);
    if (win32.ShellExecute(0, operation, tool, arguments, nullptr,
            win32.SHOW_WINDOW_CMD.SW_HIDE) <=
        32) {
      throw StateError('Windows did not start the service command.');
    }
  });
}
