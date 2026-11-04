
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String apiKey = String.fromEnvironment('API_FOOTBALL_KEY');
const String apiBase = 'https://v3.football.api-sports.io';

const String supabaseUrl = 'https://eojfbquyapkjarxpyigw.supabase.co';
const String supabasePublishableKey = 'PASTE_YOUR_SB_PUBLISHABLE_KEY_HERE';

const Color brandRed = Color(0xFFD50000);
const Color winGreen = Color(0xFF218838);
const Color drawGold = Color(0xFFFFC107);
const Color lostRed = Color(0xFFD50000);
const String appLogo = 'assets/boom_logo.png';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabasePublishableKey,
  );

  runApp(const BoomgratulationsApp());
}

class BoomgratulationsApp extends StatelessWidget {
  const BoomgratulationsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BOOMGRATULATIONS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brandRed),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: brandRed,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandRed,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF9B0000),
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
