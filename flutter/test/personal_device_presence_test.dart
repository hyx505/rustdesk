import 'package:flutter_hbb/models/personal_device_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late PersonalDevicePresence model;

  setUp(() {
    now = DateTime.utc(2026);
    model = PersonalDevicePresence(now: () => now);
    model.track(['DeskA', 'DeskB'], 'ThisPc');
  });

  test('waits for a reply and follows online and offline transitions', () {
    expect(model.queryIds, ['ThisPc', 'DeskA', 'DeskB']);
    expect(model.status('DeskA'), DevicePresence.checking);

    expect(model.apply({'onlines': 'DeskA', 'offlines': 'DeskB'}), isFalse);
    expect(model.status('DeskB'), DevicePresence.checking);

    expect(
        model.apply({'onlines': 'ThisPc,DeskA', 'offlines': 'DeskB'}), isTrue);
    expect(model.status('DeskA'), DevicePresence.online);
    expect(model.status('DeskB'), DevicePresence.offline);

    expect(
        model.apply({'onlines': 'ThisPc,DeskB', 'offlines': 'DeskA'}), isTrue);
    expect(model.status('DeskA'), DevicePresence.offline);
    expect(model.status('DeskB'), DevicePresence.online);
  });

  test('missing results and ambiguous all-offline replies are unknown', () {
    now = now.add(const Duration(seconds: 20));
    expect(model.status('DeskA'), DevicePresence.unknown);

    model.apply({'onlines': 'ThisPc,DeskA', 'offlines': 'DeskB'});
    expect(model.status('DeskA'), DevicePresence.online);
    expect(
        model.apply({'onlines': '', 'offlines': 'ThisPc,DeskA,DeskB'}), isTrue);
    expect(model.status('DeskA'), DevicePresence.unknown);
    expect(model.status('DeskB'), DevicePresence.unknown);
  });

  test('valid replies refresh the expiry even when the state is unchanged', () {
    final reply = {'onlines': 'ThisPc,DeskA', 'offlines': 'DeskB'};
    expect(model.apply(reply), isTrue);
    now = now.add(const Duration(seconds: 19));
    expect(model.apply(reply), isFalse);
    now = now.add(const Duration(seconds: 19));
    expect(model.status('DeskA'), DevicePresence.online);
    now = now.add(const Duration(seconds: 1));
    expect(model.status('DeskA'), DevicePresence.unknown);
  });

  test('updates the known devices and ignores replies for the old local ID',
      () {
    model.apply({'onlines': 'ThisPc,DeskA', 'offlines': 'DeskB'});
    expect(model.track(['DeskA', 'DeskOther@another-server'], 'NewPc'), isTrue);
    expect(model.queryIds, ['NewPc', 'DeskA']);
    expect(model.status('DeskB'), DevicePresence.unknown);
    expect(model.status('DeskOther@another-server'), DevicePresence.unknown);
    expect(
        model.apply({'onlines': 'ThisPc,DeskA', 'offlines': 'DeskB'}), isFalse);
    expect(model.status('DeskA'), DevicePresence.checking);
  });

  test('devices are unknown until the local registration ID is available', () {
    model.track(['DeskA'], '');
    expect(model.queryIds, isEmpty);
    expect(model.status('DeskA'), DevicePresence.unknown);
    model.track(['DeskA'], 'ThisPc');
    expect(model.status('DeskA'), DevicePresence.checking);
  });
}
