import 'package:cinemakom/app/l10n/app_localizations.dart';
import 'package:cinemakom/features/settings/report_flow.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const info = (version: '1.2.0 (7)', device: 'OnePlus CPH2423 · Android 15');

  test('the email goes to the address, with questions and the device', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final uri = bugReportEmailUri(l10n, info, tv: true);
    expect(uri.scheme, 'mailto');
    expect(uri.path, bugReportEmail);
    // Spaces as %20: mail apps show a "+" as is.
    expect(uri.toString(), isNot(contains('+')));
    final body = Uri.decodeComponent(uri.toString().split('&body=').last);
    expect(body, startsWith('What happened?'));
    expect(body, contains('Cinemakom 1.2.0 (7) · TV'));
    expect(body, contains('OnePlus CPH2423 · Android 15'));
    expect(body, contains('App language: English'));
  });

  test('GitHub opens the bug form with the version and device', () {
    final uri = bugReportGithubUri(info);
    expect(uri.path, '/sharon-xa/cinemakom/issues/new');
    expect(uri.queryParameters['template'], 'bug_report.yml');
    expect(uri.queryParameters['version'], '1.2.0 (7)');
    expect(uri.queryParameters['device'], 'OnePlus CPH2423 · Android 15');
  });
}
