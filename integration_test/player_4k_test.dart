// Measures 4K (and 1080p) smoothness on a real device, per video output
// mode: mpv's decoder mode, dropped and late frames, and the buffer (to
// tell decoding from network trouble). Run on the phone:
//   fvm flutter test integration_test/player_4k_test.dart -d <phone>
// Results are printed as "4K ..." lines.
import 'package:cinemakom/core/network/api_client.dart';
import 'package:cinemakom/data/repositories/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

const movieId = '191463'; // Avengers: 240p–1080p and 4K

const _props = [
  'hwdec-current',
  'video-codec',
  'video-params/w',
  'container-fps',
  'estimated-vf-fps',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'vo-delayed-frame-count',
  'mistimed-frame-count',
  'vsync-jitter',
  'demuxer-cache-duration',
  'paused-for-cache',
];

Future<void> live(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();
  final repo = MediaRepository(ApiClient());

  // (label, extra mpv options) on 4K with media_kit's default output.
  const cases = <(String, Map<String, String>)>[
    ('default', {}),
    ('swapinterval 0', {'opengl-swapinterval': '0'}),
    ('display-resample', {'video-sync': 'display-resample'}),
    ('framedrop no', {'framedrop': 'no'}),
    ('swapinterval 0 + framedrop no', {
      'opengl-swapinterval': '0',
      'framedrop': 'no',
    }),
  ];
  const height = 2160;
  const String? vo = null;
  const String? hwdec = null;

  for (final (label, extra) in cases) {
    testWidgets('$height $label', (tester) async {
      final sources = await repo.streams(movieId);
      final src = sources.firstWhere((s) => s.height == height);
      final player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 64 * 1024 * 1024,
        ),
      );
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: vo,
          hwdec: hwdec,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Video(controller: controller, controls: NoVideoControls),
          ),
        ),
      );
      final native = player.platform! as NativePlayer;
      for (final MapEntry(:key, :value) in {
        'ytdl': 'no',
        'network-timeout': '20',
        'cache-on-disk': 'no',
        'demuxer-readahead-secs': '20',
        'cache-secs': '30',
        ...extra,
      }.entries) {
        await native.setProperty(key, value);
      }
      await player.open(
        Media(
          src.url,
          httpHeaders: ApiClient.defaultHeaders,
          start: const Duration(minutes: 10),
        ),
      );
      // Warm up (open and fill the buffer), then count over 25 s.
      await live(tester, const Duration(seconds: 8));
      Future<Map<String, String>> read() async => {
        for (final p in _props) p: await native.getProperty(p),
      };
      final before = await read();
      await live(tester, const Duration(seconds: 25));
      final after = await read();
      String delta(String p) =>
          '${(int.tryParse(after[p]!) ?? 0) - (int.tryParse(before[p]!) ?? 0)}';
      // ignore: avoid_print
      print(
        '4K $height $label vo=${vo ?? 'default'}: '
        'hwdec=${after['hwdec-current']} codec=${after['video-codec']} '
        'w=${after['video-params/w']} fps=${after['container-fps']} '
        'shown=${after['estimated-vf-fps']} '
        'dropped=${delta('frame-drop-count')} '
        'decoderDropped=${delta('decoder-frame-drop-count')} '
        'late=${delta('vo-delayed-frame-count')} '
        'mistimed=${delta('mistimed-frame-count')} '
        'jitter=${after['vsync-jitter']} '
        'buffer=${after['demuxer-cache-duration']}s '
        'waitingForNetwork=${after['paused-for-cache']}',
      );
      await player.dispose();
    });
  }
}
