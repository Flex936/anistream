import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  // Ensures component bindings are ready before initialization
  WidgetsFlutterBinding.ensureInitialized();

  // Directs libmpv to spin up its native rendering context
  MediaKit.ensureInitialized();

  runApp(const AniStreamApp());
}

class AniStreamApp extends StatelessWidget {
  const AniStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniStream',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
      ),
      home: const TheaterTestScreen(),
    );
  }
}

class TheaterTestScreen extends StatefulWidget {
  const TheaterTestScreen({super.key});

  @override
  State<TheaterTestScreen> createState() => _TheaterTestScreenState();
}

class _TheaterTestScreenState extends State<TheaterTestScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    // Opens a reliable public test stream to verify the hardware decoding pipeline
    player.open(Media('http://localhost:8080/stream'));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // The native video layer rendering underneath
          Center(
            child: SizedBox(
              width: 1280,
              height: 720,
              child: Video(controller: controller),
            ),
          ),
          // Proof of concept: This text overlays natively on top of the video canvas
          Positioned(
            top: 40,
            left: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "AniStream Native Canvas Test",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
