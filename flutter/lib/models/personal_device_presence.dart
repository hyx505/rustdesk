enum DevicePresence {
  checking('查询中'),
  online('在线'),
  offline('离线'),
  unknown('状态未知');

  const DevicePresence(this.label);
  final String label;
}

class PersonalDevicePresence {
  PersonalDevicePresence({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static const _freshFor = Duration(seconds: 20);
  static final _registeredId = RegExp(r'^[a-zA-Z0-9_-]+$');
  final DateTime Function() _now;
  final _knownSince = <String, DateTime>{};
  final _reports = <String, (DevicePresence, DateTime)>{};
  String _localId = '';

  bool track(Iterable<String> peers, String localId) {
    final ids = peers
        .where((id) => id != localId && _registeredId.hasMatch(id))
        .toSet();
    final reference = _registeredId.hasMatch(localId) ? localId : '';
    if (reference == _localId &&
        ids.length == _knownSince.length &&
        ids.every(_knownSince.containsKey)) {
      return false;
    }
    if (reference != _localId) {
      _localId = reference;
      _knownSince.clear();
      _reports.clear();
    }
    _knownSince.removeWhere((id, _) => !ids.contains(id));
    _reports.removeWhere((id, _) => !ids.contains(id));
    final now = _now();
    for (final id in ids) {
      _knownSince.putIfAbsent(id, () => now);
    }
    return true;
  }

  List<String> get queryIds => _localId.isEmpty || _knownSince.isEmpty
      ? const []
      : [_localId, ..._knownSince.keys];

  bool apply(Map<String, dynamic> event) {
    Set<String> split(dynamic ids) => ids is String
        ? ids.split(',').where((id) => id.isNotEmpty).toSet()
        : {};
    final onlines = split(event['onlines']);
    final offlines = split(event['offlines']);

    // The bridge also emits events for autocomplete and device management.
    // Include our own ID in each dashboard query to recognize its replies.
    if (!onlines.contains(_localId) && !offlines.contains(_localId)) {
      return false;
    }

    // On connect/send failure, older native clients synthesize a reply with
    // every ID offline. A registered local ID (or any online peer) confirms
    // that a response came from the server.
    final offlineState =
        onlines.isEmpty ? DevicePresence.unknown : DevicePresence.offline;
    var changed = false;
    final now = _now();
    for (final (ids, state) in [
      (onlines, DevicePresence.online),
      (offlines, offlineState),
    ]) {
      for (final id in ids) {
        if (!_knownSince.containsKey(id)) continue;
        changed = status(id) != state || changed;
        _reports[id] = (state, now);
      }
    }
    return changed;
  }

  DevicePresence status(String id) {
    if (_localId.isEmpty) return DevicePresence.unknown;
    final now = _now();
    final report = _reports[id];
    if (report != null) {
      final (state, at) = report;
      return now.difference(at) < _freshFor ? state : DevicePresence.unknown;
    }
    final added = _knownSince[id];
    return added != null && now.difference(added) < _freshFor
        ? DevicePresence.checking
        : DevicePresence.unknown;
  }
}
