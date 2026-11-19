import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show gFFI;
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const _groupsOption = 'personal-remote-device-groups';

class PersonalDevices extends StatefulWidget {
  const PersonalDevices({super.key});

  @override
  State<PersonalDevices> createState() => _PersonalDevicesState();
}

class _PersonalDevicesState extends State<PersonalDevices> {
  final _groups = <String>{};
  final _devices = <String, String>{};
  var _tab = PeerTabIndex.fav;
  String? _group;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw = bind.mainGetLocalOption(key: _groupsOption);
    if (raw.isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return;
      final groups = data['groups'];
      if (groups is List) {
        _groups.addAll(
            groups.whereType<String>().where((name) => name.isNotEmpty));
      }
      final devices = data['devices'];
      if (devices is Map<String, dynamic>) {
        for (final entry in devices.entries) {
          final name = entry.value;
          if (name is String && _groups.contains(name)) {
            _devices[entry.key] = name;
          }
        }
      }
    } on FormatException {
      debugPrint('The local device groups could not be parsed.');
    }
  }

  Future<void> _save(Set<String> groups, Map<String, String> devices) async {
    if (_saving || !mounted) return;
    setState(() => _saving = true);
    try {
      await bind.mainSetLocalOption(
        key: _groupsOption,
        value: jsonEncode({'groups': groups.toList(), 'devices': devices}),
      );
      if (!mounted) return;
      setState(() {
        _groups
          ..clear()
          ..addAll(groups);
        _devices
          ..clear()
          ..addAll(devices);
        if (_group?.isNotEmpty == true && !_groups.contains(_group)) {
          _group = null;
        }
      });
    } catch (error) {
      debugPrint('Could not save local device groups: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分组保存失败，请重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addGroup() async {
    var name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final duplicate = _groups.contains(name);
          return AlertDialog(
            title: const Text('新建分组'),
            content: TextField(
              autofocus: true,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: '分组名称',
                errorText: duplicate ? '已有同名分组' : null,
              ),
              onChanged: (value) => setDialogState(() => name = value.trim()),
              onSubmitted: (_) {
                if (name.isNotEmpty && !duplicate) Navigator.pop(context, name);
              },
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              FilledButton(
                onPressed: name.isEmpty || duplicate
                    ? null
                    : () => Navigator.pop(context, name),
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) await _save({..._groups, result}, Map.of(_devices));
  }

  Future<void> _deleteGroup(String group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除分组「$group」？'),
        content: const Text('组内设备将移到「未分组」。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _save(
        {..._groups}..remove(group),
        Map.of(_devices)..removeWhere((_, name) => name == group),
      );
    }
  }

  Future<void> _moveToGroup(BuildContext _, Peer peer) async {
    if (!mounted || _saving) return;
    final group = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('移动 ${peer.getId()}'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('未分组'),
          ),
          for (final name in _groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (group == null) return;
    final devices = Map.of(_devices);
    if (group.isEmpty) {
      devices.remove(peer.id);
    } else {
      devices[peer.id] = group;
    }
    await _save(Set.of(_groups), devices);
  }

  void _selectTab(PeerTabIndex tab) {
    if (_tab == tab) return;
    gFFI.peerTabModel.setCurrentTab(tab.index);
    setState(() => _tab = tab);
  }

  Widget _peerList() {
    switch (_tab) {
      case PeerTabIndex.fav:
        return FavoritePeersView(
          key: const ValueKey('personal-favorites'),
          menuPadding: kDesktopMenuPadding,
          showConnect: true,
          onMoveToGroup: _saving ? null : _moveToGroup,
          filter: (peer) =>
              _group == null || (_devices[peer.id] ?? '') == _group,
        );
      case PeerTabIndex.lan:
        return DiscoveredPeersView(
          key: const ValueKey('personal-lan'),
          menuPadding: kDesktopMenuPadding,
          showConnect: true,
          onWake: (context, peer) => showDialog<void>(
            context: context,
            builder: (_) => _WakeDeviceDialog(peer: peer),
          ),
        );
      default:
        return RecentPeersView(
          key: const ValueKey('personal-recent'),
          menuPadding: kDesktopMenuPadding,
          showConnect: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedGroup = _group;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('我的设备', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          TextField(
            controller: peerSearchTextController,
            onChanged: (value) => peerSearchText.value = value,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded),
              hintText: '搜索设备 ID、名称或别名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (tab, label) in const [
                (PeerTabIndex.fav, '收藏'),
                (PeerTabIndex.recent, '最近连接'),
                (PeerTabIndex.lan, '局域网'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _tab == tab,
                  onSelected: (_) => _selectTab(tab),
                ),
            ],
          ),
          if (_tab == PeerTabIndex.fav)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                    width: 172,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedGroup,
                      hint: const Text('所有分组'),
                      items: [
                        const DropdownMenuItem<String>(
                            value: null, child: Text('所有分组')),
                        const DropdownMenuItem(value: '', child: Text('未分组')),
                        for (final name in _groups)
                          DropdownMenuItem(
                              value: name,
                              child:
                                  Text(name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _saving
                          ? null
                          : (group) => setState(() => _group = group),
                    )),
                IconButton(
                  tooltip: '新建分组',
                  onPressed: _saving ? null : _addGroup,
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
                if (selectedGroup != null && selectedGroup.isNotEmpty)
                  IconButton(
                    tooltip: '删除当前分组',
                    onPressed:
                        _saving ? null : () => _deleteGroup(selectedGroup),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Expanded(child: _peerList()),
        ],
      ),
    );
  }
}

class _WakeDeviceDialog extends StatefulWidget {
  const _WakeDeviceDialog({required this.peer});

  final Peer peer;

  @override
  State<_WakeDeviceDialog> createState() => _WakeDeviceDialogState();
}

class _WakeDeviceDialogState extends State<_WakeDeviceDialog> {
  Timer? _timer;
  String? _result;

  @override
  void initState() {
    super.initState();
    gFFI.lanPeersModel.addListener(_onPeersChanged);
    _start();
  }

  Future<void> _start() async {
    try {
      await bind.mainWol(id: widget.peer.id);
      if (!mounted || _result != null) return;
      bind.queryOnlines(ids: [widget.peer.id]);
      _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (timer.tick >= 20) {
          timer.cancel();
          setState(() => _result = '等待设备上线超时，请检查主机和网卡的唤醒设置。');
          return;
        }
        bind.queryOnlines(ids: [widget.peer.id]);
      });
    } catch (error) {
      debugPrint('Could not request Wake-on-LAN: $error');
      if (mounted) setState(() => _result = '唤醒请求失败。');
    }
  }

  void _onPeersChanged() {
    if (_result != null) return;
    if (gFFI.lanPeersModel.peers
        .any((peer) => peer.id == widget.peer.id && peer.online)) {
      _timer?.cancel();
      setState(() => _result = '设备已上线。');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    gFFI.lanPeersModel.removeListener(_onPeersChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('唤醒 ${widget.peer.getId()}'),
        content: Text(_result ?? '正在等待设备上线…'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      );
}
