import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'personal_devices.dart';

enum _Page { device, all, assistance, favorites }

enum _Action {
  desktop('进入桌面', Icons.desktop_windows_outlined),
  files('文件传输', Icons.drive_folder_upload_outlined),
  terminal('终端', Icons.terminal),
  tunnel('端口映射', Icons.cable_outlined);

  const _Action(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _shortcutsKey = 'personal-remote-quick-launch';
const _blue = Color(0xff337bff);

class PersonalHome extends StatefulWidget {
  const PersonalHome({
    super.key,
    required this.assistance,
    this.openSettings,
  });

  final Widget assistance;
  final VoidCallback? openSettings;

  @override
  State<PersonalHome> createState() => _PersonalHomeState();
}

class _PersonalHomeState extends State<PersonalHome> {
  late final _models = [
    gFFI.favoritePeersModel,
    gFFI.recentPeersModel,
    gFFI.lanPeersModel,
  ];
  late final _changes = Listenable.merge(
      [..._models, gFFI.serverModel, gFFI.serverModel.serverId]);
  late final Timer _poll;
  _Page _page = _Page.device;
  String? _selectedId;
  bool _homeVisible = true;
  bool _devicesExpanded = true;
  bool _assistanceExpanded = true;
  late final _shortcuts = bind
      .mainGetLocalOption(key: _shortcutsKey)
      .split(',')
      .where(_Action.values.map((action) => action.name).contains)
      .toSet();

  @override
  void initState() {
    super.initState();
    unawaited(bind.mainLoadFavPeers());
    unawaited(bind.mainLoadRecentPeers());
    unawaited(bind.mainLoadLanPeers());
    unawaited(bind.mainDiscover());
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_page != _Page.device || !_homeVisible) return;
      final ids = _peers().map((peer) => peer.id).take(100).toList();
      if (ids.isNotEmpty) unawaited(bind.queryOnlines(ids: ids));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _homeVisible = TickerMode.of(context);
  }

  @override
  void dispose() {
    _poll.cancel();
    super.dispose();
  }

  List<Peer> _peers() {
    final self = gFFI.serverModel.serverId.text.replaceAll(' ', '');
    final peers = <String, Peer>{};
    for (final model in _models) {
      for (final peer in model.peers) {
        if (peer.id.isEmpty || peer.id == self) continue;
        final previous = peers.putIfAbsent(peer.id, () => peer);
        if (!previous.online && peer.online) peers[peer.id] = peer;
      }
    }
    return peers.values.toList();
  }

  String _name(Peer peer) {
    if (peer.alias.isNotEmpty) return peer.alias;
    return peer.hostname.isEmpty ? formatID(peer.id) : peer.hostname;
  }

  void _navigate(_Page page, [Peer? peer]) {
    setState(() {
      _page = page;
      _selectedId = peer?.id;
    });
  }

  void _launch(Peer peer, _Action action, {bool forceRelay = false}) {
    connect(
      context,
      peer.id,
      isFileTransfer: action == _Action.files,
      isTerminal: action == _Action.terminal,
      isTcpTunneling: action == _Action.tunnel,
      forceRelay: forceRelay || peer.forceAlwaysRelay,
    );
  }

  Future<void> _setShortcut(_Action action, bool enabled) async {
    setState(() {
      if (enabled) {
        _shortcuts.add(action.name);
      } else {
        _shortcuts.remove(action.name);
      }
    });
    await bind.mainSetLocalOption(
        key: _shortcutsKey, value: _shortcuts.join(','));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rail = dark ? const Color(0xff20272d) : const Color(0xffedf2f5);
    final canvas = dark ? const Color(0xff171e24) : const Color(0xfff5f8fa);
    final line = dark ? Colors.white12 : const Color(0xffdce4e9);
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        final peers = _peers();
        final selected =
            peers.firstWhereOrNull((peer) => peer.id == _selectedId) ??
                peers.firstOrNull;
        return LayoutBuilder(builder: (context, size) {
          final railWidth = (size.maxWidth * .26).clamp(165.0, 300.0);
          return ColoredBox(
            color: rail,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: railWidth, child: _rail(peers, selected, line)),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: canvas,
                      border: Border(
                          top: BorderSide(color: line),
                          left: BorderSide(color: line)),
                      borderRadius:
                          const BorderRadius.only(topLeft: Radius.circular(12)),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Offstage(
                          offstage: _page != _Page.assistance,
                          child: TickerMode(
                            enabled: _page == _Page.assistance,
                            child: ExcludeFocus(
                              excluding: _page != _Page.assistance,
                              child: widget.assistance,
                            ),
                          ),
                        ),
                        if (_page == _Page.device)
                          _device(selected, line, dark),
                        if (_page == _Page.all)
                          const PersonalDevices(
                              key: ValueKey('all-devices'),
                              startOnRecent: true),
                        if (_page == _Page.favorites)
                          const PersonalDevices(
                              key: ValueKey('favorite-devices')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _rail(List<Peer> peers, Peer? selected, Color line) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(5, 8, 5, 12),
            children: [
              _nav('我的设备', Icons.devices_outlined,
                  onTap: () =>
                      setState(() => _devicesExpanded = !_devicesExpanded),
                  trailing: Icon(
                      _devicesExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 17)),
              if (_devicesExpanded) ...[
                if (peers.isEmpty)
                  _nav(Platform.localHostname, Icons.window_rounded,
                      indent: true,
                      online: gFFI.serverModel.connectStatus == 1,
                      selected: _page == _Page.device,
                      onTap: () => _navigate(_Page.device)),
                for (final peer in peers.take(20))
                  _nav(_name(peer), _deviceIcon(peer),
                      indent: true,
                      online: peer.online,
                      selected:
                          _page == _Page.device && selected?.id == peer.id,
                      onTap: () => _navigate(_Page.device, peer)),
                _nav('全部设备', Icons.grid_view_rounded,
                    indent: true,
                    accent: true,
                    selected: _page == _Page.all,
                    onTap: () => _navigate(_Page.all)),
              ],
              const SizedBox(height: 10),
              _nav('远程协助', Icons.dashboard_customize_outlined,
                  onTap: () => setState(
                      () => _assistanceExpanded = !_assistanceExpanded),
                  trailing: Icon(
                      _assistanceExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 17)),
              if (_assistanceExpanded) ...[
                _nav('开始协助', Icons.screen_share_rounded,
                    indent: true,
                    accent: true,
                    selected: _page == _Page.assistance,
                    onTap: () => _navigate(_Page.assistance)),
                _nav('收藏设备', Icons.bookmark_rounded,
                    indent: true,
                    accent: true,
                    selected: _page == _Page.favorites,
                    onTap: () => _navigate(_Page.favorites)),
              ],
            ],
          ),
        ),
        if (widget.openSettings != null) ...[
          Divider(height: 1, color: line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 11),
            child: _nav('设置', Icons.settings_outlined,
                onTap: widget.openSettings!),
          ),
        ],
      ],
    );
  }

  IconData _deviceIcon(Peer peer) => switch (peer.platform.toLowerCase()) {
        'windows' => Icons.window_rounded,
        'android' || 'ios' => Icons.smartphone_outlined,
        _ => Icons.desktop_windows_outlined,
      };

  Widget _nav(
    String label,
    IconData icon, {
    required VoidCallback onTap,
    bool selected = false,
    bool indent = false,
    bool accent = false,
    bool? online,
    Widget? trailing,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? (dark ? const Color(0xff35424c) : const Color(0xffe1e7eb))
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (selected)
                Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                        color: _blue, borderRadius: BorderRadius.circular(3))),
              Padding(
                padding: EdgeInsets.fromLTRB(indent ? 27 : 15, 0, 14, 0),
                child: SizedBox(
                  height: 45,
                  child: Row(children: [
                    if (indent) ...[
                      SizedBox(
                          width: 9,
                          child: online == true
                              ? const _OnlineDot(size: 7)
                              : null),
                      const SizedBox(width: 10),
                    ],
                    Icon(icon,
                        size: indent ? 23 : 20,
                        color: accent || selected
                            ? _blue
                            : online == false
                                ? const Color(0xff89939a)
                                : null),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15))),
                    if (trailing != null) trailing,
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _device(Peer? peer, Color line, bool dark) {
    final self = peer == null;
    final online = peer?.online ?? (gFFI.serverModel.connectStatus == 1);
    return LayoutBuilder(builder: (context, size) {
      final inset = size.maxWidth > 680 ? 48.0 : 20.0;
      return ListView(
        padding: EdgeInsets.fromLTRB(inset, 22, inset, 30),
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                    color: const Color(0xff171b1e),
                    borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (online)
                      const _OnlineDot(size: 8)
                    else
                      const Icon(Icons.circle, size: 8, color: Colors.white38),
                    const SizedBox(width: 5),
                    Text(
                        online
                            ? '在线'
                            : self
                                ? '未就绪'
                                : '离线',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                  child: Text(
                      peer == null ? Platform.localHostname : _name(peer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 31, fontWeight: FontWeight.w700))),
              if (peer != null)
                PopupMenuButton<bool>(
                  tooltip: '设备操作',
                  onSelected: (relay) {
                    if (relay) {
                      _launch(peer, _Action.desktop, forceRelay: true);
                    } else {
                      _navigate(_Page.all);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: true, child: Text('通过中继连接')),
                    PopupMenuItem(value: false, child: Text('管理设备')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 27),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: (size.maxWidth * .355).clamp(170.0, 310.0),
                  child: PersonalDesktopTile(
                    label: self ? '开始协助' : '进入桌面',
                    onTap: peer == null
                        ? () => _navigate(_Page.assistance)
                        : () => _launch(peer, _Action.desktop),
                  ),
                ),
                _actionStrip(peer, line, dark),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(self ? '远程协助' : '快速启动', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 9),
          if (peer == null)
            _shortcutArea(line,
                child: _QuickItem(
                    icon: Icons.add,
                    label: '连接设备',
                    onTap: () => _navigate(_Page.assistance)))
          else
            _shortcutArea(line,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    for (final action in _Action.values)
                      if (_shortcuts.contains(action.name))
                        _QuickItem(
                          icon: action.icon,
                          label: action.label,
                          onTap: () => _launch(peer, action),
                          onRemove: () => _setShortcut(action, false),
                        ),
                    if (_shortcuts.length < _Action.values.length)
                      PopupMenuButton<_Action>(
                        tooltip: '添加快捷操作',
                        onSelected: (action) => _setShortcut(action, true),
                        itemBuilder: (_) => [
                          for (final action in _Action.values)
                            if (!_shortcuts.contains(action.name))
                              PopupMenuItem(
                                  value: action, child: Text(action.label)),
                        ],
                        child: const _QuickItem(icon: Icons.add, label: '添加'),
                      ),
                  ],
                )),
        ],
      );
    });
  }

  Widget _shortcutArea(Color line, {required Widget child}) {
    return CustomPaint(
      painter: _DashedFrame(line),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 184),
        child: Center(
            child: Padding(
          padding: const EdgeInsets.all(12),
          child: child,
        )),
      ),
    );
  }

  Widget _actionStrip(Peer? peer, Color line, bool dark) {
    final actions = peer == null
        ? [
            (
              Icons.screen_share_outlined,
              '开始协助',
              () => _navigate(_Page.assistance)
            ),
            (Icons.grid_view_rounded, '全部设备', () => _navigate(_Page.all)),
          ]
        : [
            for (final action in [
              _Action.files,
              _Action.terminal,
              _Action.tunnel
            ])
              (action.icon, action.label, () => _launch(peer, action)),
            (Icons.grid_view_rounded, '全部设备', () => _navigate(_Page.all)),
          ];
    return Material(
      color: dark ? const Color(0xff27313a) : Colors.white,
      child: SizedBox(
        height: 60,
        child: Row(children: [
          for (final (index, (icon, label, callback)) in actions.indexed) ...[
            if (index > 0) Container(width: 1, height: 24, color: line),
            Expanded(
                child: Tooltip(
              message: label,
              child: InkWell(
                onTap: callback,
                child: Center(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 19),
                          const SizedBox(width: 8),
                          Text(label, style: const TextStyle(fontSize: 15)),
                        ],
                      )),
                )),
              ),
            )),
          ],
        ]),
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
            color: Color(0xff21e99a), shape: BoxShape.circle),
      );
}

class PersonalDesktopTile extends StatelessWidget {
  const PersonalDesktopTile(
      {super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xff10091f),
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff09051a), Color(0xff1c0946), Color(0xff2d100d)],
            ),
          ),
          child: CustomPaint(
            painter: const _DesktopGlow(),
            child: InkWell(
              onTap: onTap,
              hoverColor: Colors.white10,
              focusColor: Colors.white12,
              child: Align(
                alignment: const Alignment(0, .56),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(width: 16),
                  const Icon(Icons.east_rounded, color: Colors.white, size: 23),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _DesktopGlow extends CustomPainter {
  const _DesktopGlow();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .53, size.height * .74);
    final radius = size.width * .44;
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xff92159a), Color(0x88470bbc), Color(0x00231770)],
            stops: [0, .48, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)));
    final ring = Rect.fromCenter(
        center: Offset(size.width * .50, size.height * .30),
        width: size.width * .66,
        height: size.height * 1.68);
    canvas.drawArc(
        ring,
        .08,
        math.pi - .16,
        false,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0x007f46ff),
              Color(0xff4c20db),
              Color(0xffdf2162),
              Color(0x00ce1468)
            ],
          ).createShader(ring)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
  }

  @override
  bool shouldRepaint(_DesktopGlow oldDelegate) => false;
}

class _DashedFrame extends CustomPainter {
  const _DashedFrame(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5), const Radius.circular(6)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final metric in border.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 11) {
        canvas.drawPath(
            metric.extractPath(offset, math.min(offset + 7, metric.length)),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame oldDelegate) => color != oldDelegate.color;
}

class _QuickItem extends StatelessWidget {
  const _QuickItem(
      {required this.icon, required this.label, this.onTap, this.onRemove});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor:
                      Theme.of(context).colorScheme.onSurface.withOpacity(.07),
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: Icon(icon, size: 23),
                ),
                const SizedBox(height: 7),
                Text(label),
              ]),
            ),
          ),
          if (onRemove != null)
            IconButton(
                tooltip: '移除快捷操作',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 14)),
        ],
      );
}
