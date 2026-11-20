part of 'desktop_setting_page.dart';

const _personalAccent = Color(0xff337bff);

enum _PersonalSettingsTab {
  general('常规', SettingsTabKey.general),
  security('安全', SettingsTabKey.safety),
  keyboard('键盘'),
  network('网络', SettingsTabKey.network),
  display('显示', SettingsTabKey.display),
  printer('打印', SettingsTabKey.printer),
  about('关于', SettingsTabKey.about);

  const _PersonalSettingsTab(this.label, [this.key]);
  final String label;
  final SettingsTabKey? key;
}

class _PersonalSettings extends StatefulWidget {
  const _PersonalSettings({required this.initial});

  final SettingsTabKey initial;

  @override
  State<_PersonalSettings> createState() => _PersonalSettingsState();
}

class _PersonalSettingsState extends State<_PersonalSettings> {
  final _keyboard = GlobalKey<KeyboardShortcutsPageBodyState>();
  late final _tabs = _PersonalSettingsTab.values
      .where((tab) =>
          tab.key == null || DesktopSettingPage.tabKeys.contains(tab.key))
      .toList();
  late var _selected = _tabs.firstWhere((tab) => tab.key == widget.initial,
      orElse: () => _tabs.first);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final inset = box.maxWidth > 680 ? 48.0 : 20.0;
      return _PersonalSettingsScope(
        child: Padding(
          padding: EdgeInsets.fromLTRB(inset, 24, inset, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('设置',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final tab in _tabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 27),
                      child: _tab(context, tab),
                    ),
                ]),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: switch (_selected) {
                  _PersonalSettingsTab.general => const _General(),
                  _PersonalSettingsTab.security => const _Safety(),
                  _PersonalSettingsTab.keyboard => _shortcuts(),
                  _PersonalSettingsTab.network => const _Network(),
                  _PersonalSettingsTab.display => const _Display(),
                  _PersonalSettingsTab.printer => const _Printer(),
                  _PersonalSettingsTab.about => const _About(),
                },
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _tab(BuildContext context, _PersonalSettingsTab tab) {
    final selected = tab == _selected;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => setState(() => _selected = tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 7),
          child: Column(children: [
            Text(tab.label,
                style: TextStyle(
                    fontSize: 16,
                    color: selected ? null : Theme.of(context).hintColor)),
            const SizedBox(height: 7),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 19,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? _personalAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _shortcuts() => KeyboardShortcutsPageBody(
        key: _keyboard,
        compact: true,
        settingsStyle: true,
        headerBanner: _PersonalSettingsCard(children: [
          _PersonalSettingsRow(
            icon: Icons.keyboard_outlined,
            title: '功能快捷键',
            child: OutlinedButton(
              onPressed: () =>
                  _keyboard.currentState?.resetToDefaultsWithConfirm(),
              child: const Text('还原默认按键'),
            ),
          ),
        ]),
      );
}

class _PersonalSettingsScope extends InheritedWidget {
  const _PersonalSettingsScope({required super.child});

  static bool enabled(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PersonalSettingsScope>() !=
      null;

  @override
  bool updateShouldNotify(_PersonalSettingsScope oldWidget) => false;
}

class _PersonalSettingsCard extends StatelessWidget {
  const _PersonalSettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: dark ? const Color(0xff252e35) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
          side: BorderSide(
              color: dark ? Colors.white12 : const Color(0xffdce2e7)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

class _PersonalSettingsRow extends StatelessWidget {
  const _PersonalSettingsRow({
    required this.title,
    required this.child,
    this.description,
    this.icon,
  });
  final String title;
  final String? description;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: description == null ? 68 : 82),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(children: [
          if (icon != null) Icon(icon, size: 22),
          if (icon != null) const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 16)),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(description!,
                      style: TextStyle(
                          fontSize: 13, color: Theme.of(context).hintColor)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          child,
        ]),
      ),
    );
  }
}

class _PersonalSettingsSwitch extends StatelessWidget {
  const _PersonalSettingsSwitch({required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value ? '开' : '关'),
        const SizedBox(width: 9),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: _personalAccent,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]);
}

class _PersonalSettingsSelect extends StatelessWidget {
  const _PersonalSettingsSelect({
    required this.current,
    required this.entries,
    this.onChanged,
  });
  final String current;
  final Map<String, String> entries;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(.35)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: entries.containsKey(current) ? current : entries.keys.first,
          isDense: true,
          style: Theme.of(context).textTheme.bodySmall,
          items: [
            for (final entry in entries.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: onChanged == null
              ? null
              : (key) {
                  if (key != null) onChanged!(key);
                },
        ),
      ),
    );
  }
}

class _PersonalSettingsAdvanced extends StatelessWidget {
  const _PersonalSettingsAdvanced({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: const Text('展开更多设置'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        children: children,
      );
}
