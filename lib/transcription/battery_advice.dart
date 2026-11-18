import '../platform/platform_bridge.dart';

/// Avertissements à montrer avant de lancer une longue transcription.
enum BatteryWarning { lowBattery, powerSave }

/// Seuil sous lequel on conseille de brancher le téléphone.
const int kLowBatteryPercent = 30;

/// Durée minimale (en minutes d'audio) à partir de laquelle les avertissements
/// batterie sont pertinents.
const int kLongJobMinutes = 10;

List<BatteryWarning> batteryWarnings(BatteryInfo info, {required int audioMinutes}) {
  final warnings = <BatteryWarning>[];
  if (audioMinutes < kLongJobMinutes) return warnings;
  if (!info.charging && info.level >= 0 && info.level < kLowBatteryPercent) {
    warnings.add(BatteryWarning.lowBattery);
  }
  if (info.powerSave) warnings.add(BatteryWarning.powerSave);
  return warnings;
}
