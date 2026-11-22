import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/l10n/app_localizations.dart';

// Bug reports and the project's page (Settings → Help), shared by the phone
// and TV UIs. There is no server: a report opens the user's mail app, or
// GitHub's issue form (.github/ISSUE_TEMPLATE/bug_report.yml), filled in
// with the app's version and the device, so the user only says what
// happened. Email comes first: most users have no GitHub account.

const projectUrl = 'https://github.com/sharon-xa/cinemakom';

/// [projectUrl] without the scheme, to show or type ("github.com/…").
const projectUrlShort = 'github.com/sharon-xa/cinemakom';

const bugReportEmail = 'me@sharon-xa.com';

/// What a report says about the app and the device.
typedef BugReportInfo = ({String version, String device});

/// The app's version and the device ("OnePlus CPH2423 · Android 15").
/// A provider, so tests (where platform channels never answer) override it.
final bugReportInfoProvider = FutureProvider<BugReportInfo>((ref) async {
  final package = await PackageInfo.fromPlatform();
  final version = '${package.version} (${package.buildNumber})';
  final info = DeviceInfoPlugin();
  final String device;
  if (Platform.isAndroid) {
    final a = await info.androidInfo;
    device = '${a.manufacturer} ${a.model} · Android ${a.version.release}';
  } else if (Platform.isIOS) {
    final i = await info.iosInfo;
    device = '${i.utsname.machine} · ${i.systemName} ${i.systemVersion}';
  } else if (Platform.isLinux) {
    device = (await info.linuxInfo).prettyName;
  } else if (Platform.isWindows) {
    final w = await info.windowsInfo;
    device = '${w.productName} ${w.displayVersion}';
  } else {
    device = Platform.operatingSystem;
  }
  return (version: version, device: device);
});

/// The "about the device" lines at the end of a report. [tv] says it came
/// from the TV UI.
String _aboutLines(AppLocalizations l10n, BugReportInfo info, bool tv) => [
  'Cinemakom ${info.version}${tv ? ' · TV' : ''}',
  info.device,
  l10n.bugReportLanguage,
].join('\n');

/// A new email to [bugReportEmail]: a subject, the questions to answer, and
/// the app and device at the end.
Uri bugReportEmailUri(
  AppLocalizations l10n,
  BugReportInfo info, {
  bool tv = false,
}) {
  final body =
      '${l10n.bugReportWhatHappened}\n\n\n'
      '${l10n.bugReportWhatDoing}\n\n\n'
      '———\n${_aboutLines(l10n, info, tv)}\n';
  // Encoded by hand: queryParameters writes spaces as "+", which mail apps
  // show as is.
  return Uri.parse(
    'mailto:$bugReportEmail'
    '?subject=${Uri.encodeComponent(l10n.bugReportSubject)}'
    '&body=${Uri.encodeComponent(body)}',
  );
}

/// GitHub's bug form with the version and device filled in (the form's
/// `version` and `device` fields).
Uri bugReportGithubUri(BugReportInfo info, {bool tv = false}) => Uri.parse(
  '$projectUrl/issues/new'
  '?template=bug_report.yml'
  '&version=${Uri.encodeComponent('${info.version}${tv ? ' · TV' : ''}')}'
  '&device=${Uri.encodeComponent(info.device)}',
);
