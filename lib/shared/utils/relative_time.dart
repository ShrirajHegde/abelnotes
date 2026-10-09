import 'package:abelnotes/l10n/app_localizations.dart';

String relativeTime(AppLocalizations l10n, DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return l10n.libTimeNow;
  if (diff.inHours < 1) return l10n.libTimeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.libTimeHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.libTimeDaysAgo(diff.inDays);
  if (diff.inDays < 30) return l10n.libTimeWeeksAgo((diff.inDays / 7).floor());
  if (diff.inDays < 365) {
    return l10n.libTimeMonthsAgo((diff.inDays / 30).floor());
  }
  return l10n.libTimeYearsAgo((diff.inDays / 365).floor());
}
