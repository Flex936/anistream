import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Import our shiny new home screen!
import 'screens/home_screen.dart';

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
        scaffoldBackgroundColor: AppPalette.base, // Uses Claude's custom token!
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppPalette.primary,
          brightness: Brightness.dark,
        ),
      ),
      // Set the initial route to Claude's new Discovery page
      home: const HomeScreen(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Temporary Theater Screen (We will move this to screens/ later)
// ════════════════════════════════════════════════════════════════════════════

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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Center(
            child: SizedBox(
              width: 1280,
              height: 720,
              child: Video(controller: controller),
            ),
          ),
        ],
      ),
    );
  }
}
