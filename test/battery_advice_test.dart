import 'package:flutter_test/flutter_test.dart';

import 'package:andika/platform/platform_bridge.dart';
import 'package:andika/transcription/battery_advice.dart';

BatteryInfo info({int level = 80, bool charging = false, bool save = false}) => BatteryInfo(
    level: level, charging: charging, powerSave: save, ignoringOptimizations: false);

void main() {
  test('court : aucun avertissement', () {
    expect(batteryWarnings(info(level: 5, save: true), audioMinutes: 3), isEmpty);
  });
  test('long avec batterie faible', () {
    expect(batteryWarnings(info(level: 20), audioMinutes: 60), [BatteryWarning.lowBattery]);
  });
  test('branché : pas d\'avertissement de niveau', () {
    expect(batteryWarnings(info(level: 20, charging: true), audioMinutes: 60), isEmpty);
  });
  test('économie d\'énergie', () {
    expect(batteryWarnings(info(save: true), audioMinutes: 30), [BatteryWarning.powerSave]);
  });
  test('niveau inconnu', () {
    expect(batteryWarnings(info(level: -1), audioMinutes: 30), isEmpty);
  });
}
