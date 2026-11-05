import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const brandRed = Color(0xFFD50000);
const apiBase = 'https://v3.football.api-sports.io';
const apiKey = String.fromEnvironment('API_FOOTBALL_KEY');
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://eojfbquyapkjarxpyigw.supabase.co',
);
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_5oOt8UA99Ud9adSfNqGPXg_LYWcQODK');
bool supabaseInitialized = false;
bool get supabaseReady => supabaseAnonKey.trim().isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseReady) {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      supabaseInitialized = true;
    } catch (_) {
      // The football app remains usable if the optional account service is unavailable.
    }
  }
  runApp(const BoomApp());
}

class BoomApp extends StatefulWidget {
  const BoomApp({super.key});
  @override
  State<BoomApp> createState() => _BoomAppState();
}
class _BoomAppState extends State<BoomApp> {
  ThemeMode mode = ThemeMode.dark;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BOOMGRATULATIONS',
    debugShowCheckedModeBanner: false,
    themeMode: mode,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: brandRed, brightness: Brightness.light),
      fontFamily: 'Montserrat',
      appBarTheme: const AppBarTheme(backgroundColor: brandRed, foregroundColor: Colors.white),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: brandRed, brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF101010),
      cardColor: const Color(0xFF1D1D1D),
      fontFamily: 'Montserrat',
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF990000), foregroundColor: Colors.white),
    ),
    home: HomeShell(onTheme: (v) => setState(() => mode = v)),
  );
}

class FootballApi {
  // API-Football's free tier can be very restrictive. Keep requests spaced,
  // reuse saved responses, and avoid duplicate requests during refreshes.
  static const Duration _fixturesCacheAge = Duration(minutes: 10);
  static const Duration _liveCacheAge = Duration(minutes: 1);
  static const Duration _minimumRequestGap = Duration(seconds: 8);
  static const Duration _rateLimitCooldown = Duration(minutes: 1);

  static final Map<String, Future<List<Map<String, dynamic>>>> _inFlight = {};
  static Future<void> _requestQueue = Future<void>.value();
  static DateTime? _lastRequestAt;
  static DateTime? _rateLimitedUntil;

    Future<List<Map<String, dynamic>>> standings(int leagueId, int season) async {
    if (apiKey.isEmpty) {
      throw Exception('Football API key is not configured.');
    }

    final cacheKey = 'boom_standings_${leagueId}_$season';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey);

    List<Map<String, dynamic>>? saved;
    DateTime? savedAt;

    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['rows'] is List) {
          saved = (decoded['rows'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          savedAt = DateTime.tryParse(decoded['savedAt']?.toString() ?? '');
        }
      } catch (_) {}
    }

    if (saved != null &&
        savedAt != null &&
        DateTime.now().difference(savedAt) < const Duration(hours: 6)) {
      return saved;
    }

    if (_rateLimitedUntil != null &&
        DateTime.now().isBefore(_rateLimitedUntil!)) {
      if (saved != null) return saved;
      throw Exception('Football API is cooling down. Try again shortly.');
    }

    try {
      final uri = Uri.parse('$apiBase/standings').replace(
        queryParameters: {
          'league': leagueId.toString(),
          'season': season.toString(),
        },
      );

      final response = await _queueRequest(() => http.get(
            uri,
            headers: {'x-apisports-key': apiKey},
          ).timeout(const Duration(seconds: 25)));

      if (response.statusCode == 429) {
        _rateLimitedUntil = DateTime.now().add(_rateLimitCooldown);
        throw Exception('Football API rate limit reached.');
      }

      if (response.statusCode != 200) {
        throw Exception('Standings service returned HTTP ${response.statusCode}.');
      }

      final body = jsonDecode(response.body);
      if (body is! Map) throw Exception('Unexpected standings response.');

      final errors = body['errors'];
      if (errors is Map && errors.isNotEmpty) {
        throw Exception(errors.values.join(', '));
      }

      final result = <Map<String, dynamic>>[];
      final responses = body['response'];

      if (responses is List && responses.isNotEmpty) {
        final league = responses.first is Map
            ? (responses.first as Map)['league'] as Map?
            : null;

        final groups = league?['standings'];

        if (groups is List) {
          for (final group in groups) {
            if (group is List) {
              for (final row in group) {
                if (row is Map) {
                  result.add(Map<String, dynamic>.from(row));
                }
              }
            }
          }
        }
      }

      await prefs.setString(cacheKey, jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'rows': result,
      }));

      _rateLimitedUntil = null;
      return result;
    } catch (_) {
      if (saved != null) return saved;
      rethrow;
    }
  }
  Future<List<Map<String, dynamic>>> fixtures({String? live, String? date}) async {
    if (apiKey.isEmpty) {
      throw Exception('Football API key is not configured in this build.');
    }

    // Use API-Football's documented `next` filter instead of `from`/`to`.
    // Some API responses reject date ranges with a validation error. `next`
    // asks for the next 20 scheduled fixtures without a date-range pair.
    final q = <String, String>{'timezone': 'Africa/Lagos'};
    if (live != null) {
      q['live'] = live;
    } else if (date != null) {
      q['date'] = date;
    } else {
      q['date'] = _date(DateTime.now());
    }

    final cacheKey = live != null
        ? 'boom_api_live_v1'
        : 'boom_api_fixtures_v3_${q['date'] ?? 'next20'}';
    final cacheAge = live != null ? _liveCacheAge : _fixturesCacheAge;
    final cached = await _readCache(cacheKey);

    if (cached != null && DateTime.now().difference(cached.savedAt) < cacheAge) {
      return cached.rows;
    }

    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;

    if (_rateLimitedUntil != null && DateTime.now().isBefore(_rateLimitedUntil!)) {
      if (cached != null) return cached.rows;
      throw Exception('Football API is cooling down after a rate limit. Please try again shortly.');
    }

    final request = _fetchAndCache(cacheKey, q, cached);
    _inFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAndCache(
    String cacheKey,
    Map<String, String> query,
    _CachedFixtures? staleCache,
  ) async {
    try {
      final uri = Uri.parse('$apiBase/fixtures').replace(queryParameters: query);
      final response = await _queueRequest(() => http.get(
        uri,
        headers: {'x-apisports-key': apiKey},
      ).timeout(const Duration(seconds: 25)));

      if (response.statusCode == 429) {
        _rateLimitedUntil = DateTime.now().add(_rateLimitCooldown);
        throw Exception('Football API rate limit reached. BOOM is using saved results and will retry shortly.');
      }
      if (response.statusCode != 200) {
        throw Exception('Football service returned HTTP ${response.statusCode}.');
      }

      final body = jsonDecode(response.body);
      if (body is! Map) throw Exception('Unexpected football service response.');
      final errors = body['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final message = errors.values.join(', ');
        if (message.toLowerCase().contains('rate limit') || message.toLowerCase().contains('too many requests')) {
          _rateLimitedUntil = DateTime.now().add(_rateLimitCooldown);
        }
        throw Exception(message);
      }

      final rows = body['response'];
      final result = rows is List
          ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'rows': result,
      }));
      _rateLimitedUntil = null;
      return result;
    } catch (_) {
      if (staleCache != null) return staleCache.rows;
      rethrow;
    }
  }

  Future<T> _queueRequest<T>(Future<T> Function() action) {
    final task = _requestQueue.then((_) async {
      final previous = _lastRequestAt;
      if (previous != null) {
        final elapsed = DateTime.now().difference(previous);
        final wait = _minimumRequestGap - elapsed;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastRequestAt = DateTime.now();
      return action();
    });
    _requestQueue = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<_CachedFixtures?> _readCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['rows'] is! List) return null;
      final savedAt = DateTime.tryParse(decoded['savedAt']?.toString() ?? '');
      if (savedAt == null) return null;
      final rows = (decoded['rows'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return _CachedFixtures(savedAt, rows);
    } catch (_) {
      return null;
    }
  }


  Future<List<Map<String, dynamic>>> endpoint(
    String path,
    Map<String, String> query,
  ) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('API-Football key is missing. Add API_FOOTBALL_KEY in GitHub Secrets.');
    }
    final uri = Uri.parse('$apiBase/$path').replace(
      queryParameters: query,
    );
    final response = await _queueRequest(() => http.get(
      uri,
      headers: {'x-apisports-key': apiKey},
    ).timeout(const Duration(seconds: 25)));
    if (response.statusCode == 429) {
      _rateLimitedUntil = DateTime.now().add(_rateLimitCooldown);
      throw Exception('API-Football rate limit reached. Please wait and retry.');
    }
    if (response.statusCode != 200) {
      throw Exception('$path returned HTTP ${response.statusCode}.');
    }
    final body = jsonDecode(response.body);
    if (body is! Map) throw Exception('Unexpected API response for $path.');
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      throw Exception(errors.values.join(', '));
    }
    final rows = body['response'];
    if (rows is! List) return <Map<String, dynamic>>[];
    return rows.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _CachedFixtures {
  const _CachedFixtures(this.savedAt, this.rows);
  final DateTime savedAt;
  final List<Map<String, dynamic>> rows;
}

class LocalStore {
  static const historyKey = 'boom_match_history_v1';
  static const noticeKey = 'boom_notifications_v1';
  static const notificationSoundKey = 'boom_notification_sound_v1';
  static Future<List<Map<String,dynamic>>> read(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
    } catch (_) {}
    return [];
  }
  static Future<void> write(String key, List<Map<String,dynamic>> value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode(value));
  }
}


const boomCompetitions = <Map<String, dynamic>>[
  {'id': 39, 'name': 'Premier League', 'country': 'England'},
  {'id': 140, 'name': 'La Liga', 'country': 'Spain'},
  {'id': 135, 'name': 'Serie A', 'country': 'Italy'},
  {'id': 78, 'name': 'Bundesliga', 'country': 'Germany'},
  {'id': 61, 'name': 'Ligue 1', 'country': 'France'},
  {'id': 2, 'name': 'UEFA Champions League', 'country': 'Europe'},
  {'id': 399, 'name': 'Nigeria Premier League', 'country': 'Nigeria'},
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onTheme});
  final ValueChanged<ThemeMode> onTheme;
  @override
  State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  bool loading = false;
  String? error;
  List<Map<String,dynamic>> matches = [];
  List<Map<String,dynamic>> live = [];
  List<Map<String,dynamic>> history = [];
  List<Map<String,dynamic>> notices = [];
  bool notificationsEnabled = true;
  bool notificationSoundEnabled = true;
  int selectedLeagueId = 39;
  int selectedSeason = 2024;
  bool standingsLoading = false;
  String? standingsError;
  List<Map<String, dynamic>> standingsRows = [];


  @override
  void initState() {
    super.initState();
    _loadLocal();
    _refresh();
  }
  Future<void> _loadLocal() async {
    final h = await LocalStore.read(LocalStore.historyKey);
    final n = await LocalStore.read(LocalStore.noticeKey);
    final prefs = await SharedPreferences.getInstance();
    final sound = prefs.getBool(LocalStore.notificationSoundKey) ?? true;
    if (mounted) {
      setState(() {
        history = h;
        notices = n;
        notificationSoundEnabled = sound;
      });
    }
  }

  Future<void> _setNotificationSound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LocalStore.notificationSoundKey, value);
    if (!mounted) return;
    setState(() => notificationSoundEnabled = value);
    _addNotice(
      'Notification sound',
      value ? 'Notification sound is ON.' : 'Notification sound is OFF.',
    );
  }
  Future<void> _refresh() async {
    if (loading) return;
    setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        FootballApi().fixtures(),
        FootballApi().fixtures(live: 'all'),
      ]);
      if (!mounted) return;
      setState(() { matches = results[0]; live = results[1]; });
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadStandings() async {
    if (standingsLoading) return;
    setState(() {
      standingsLoading = true;
      standingsError = null;
    });

    try {
      // Only the currently selected competition is requested. FootballApi
      // caches each league/season for six hours, so changing back to a
      // previously loaded league does not create another API request.
      final rows = await FootballApi().standings(selectedLeagueId, selectedSeason);
      if (!mounted) return;
      setState(() => standingsRows = rows);
    } catch (e) {
      if (mounted) {
        setState(() {
          standingsError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => standingsLoading = false);
    }
  }

  Future<void> _saveHistory(Map<String,dynamic> m) async {
    final id = ((m['fixture'] as Map?)?['id'] ?? '').toString();
    final teams = m['teams'] as Map? ?? {};
    final home = teams['home'] as Map? ?? {};
    final away = teams['away'] as Map? ?? {};
    final goals = m['goals'] as Map? ?? {};
    final item = <String,dynamic>{
      'id': id, 'home': home['name'] ?? 'Home', 'away': away['name'] ?? 'Away',
      'score': '${goals['home'] ?? '-'} - ${goals['away'] ?? '-'}',
      'league': (m['league'] as Map?)?['name'] ?? 'Football',
      'saved_at': DateTime.now().toIso8601String(),
    };
    history.removeWhere((x) => x['id'] == id && id.isNotEmpty);
    history.insert(0, item);
    if (history.length > 100) history = history.take(100).toList();
    await LocalStore.write(LocalStore.historyKey, history);
    if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Match saved to History'))); }
  }
  Future<void> _addNotice(String title, String message) async {
    notices.insert(0, {'title': title, 'message': message, 'at': DateTime.now().toIso8601String()});
    if (notices.length > 100) notices = notices.take(100).toList();
    await LocalStore.write(LocalStore.noticeKey, notices);
    if (mounted) setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    final pages = [
      _fixturesPage(), _livePage(), _picksPage(), _historyPage(), _notificationsPage(), _proPage(), _accountPage(),
    ];
    const labels = ['Home','Live','Picks','History','Alerts','Pro','Account'];
    const icons = [Icons.home_outlined,Icons.sensors,Icons.auto_awesome,Icons.history,Icons.notifications_outlined,Icons.workspace_premium,Icons.person_outline];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.asset('assets/boom_logo.png', width: 34, height: 34, fit: BoxFit.cover, errorBuilder: (_,__,___)=>const Icon(Icons.sports_soccer))),
          const SizedBox(width: 9),
          const Expanded(child: Text('BOOMGRATULATIONS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
        ]),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'light') widget.onTheme(ThemeMode.light);
              if (v == 'dark') widget.onTheme(ThemeMode.dark);
              if (v == 'system') widget.onTheme(ThemeMode.system);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value:'dark',child:Text('Dark appearance')),
              PopupMenuItem(value:'light',child:Text('Light appearance')),
              PopupMenuItem(value:'system',child:Text('System appearance')),
            ],
          ),
          IconButton(onPressed: loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        // The two secondary destinations stay at the top, as requested.
        Material(
          color: Theme.of(context).cardColor,
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => tab = 5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.workspace_premium, size: 19, color: tab == 5 ? brandRed : Colors.grey),
                    const SizedBox(width: 7),
                    Flexible(child: Text('Subscribe to Pro', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: tab == 5 ? FontWeight.w800 : FontWeight.w600,
                        color: tab == 5 ? brandRed : null))),
                  ]),
                ),
              ),
            ),
            Container(width: 1, height: 26, color: Colors.grey.withOpacity(.35)),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => tab = 4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.notifications_outlined, size: 19, color: tab == 4 ? brandRed : Colors.grey),
                    const SizedBox(width: 7),
                    Text('Alerts', style: TextStyle(fontSize: 12,
                      fontWeight: tab == 4 ? FontWeight.w800 : FontWeight.w600,
                      color: tab == 4 ? brandRed : null)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (error != null) Container(width: double.infinity, padding: const EdgeInsets.all(10), color: Colors.orange.withOpacity(.12), child: Text('Showing saved/demo content. $error', style: const TextStyle(fontSize: 11))),
        Expanded(child: pages[tab]),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: const [0, 1, 2, 6].indexOf(tab) < 0 ? 0 : const [0, 1, 2, 6].indexOf(tab),
        onDestinationSelected: (index) => setState(() => tab = const [0, 1, 2, 6][index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.sensors), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Pick'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }

  Widget _fixturesPage() => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [brandRed, Color(0xFF7F0000)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR FOOTBALL CENTRE',
                style: TextStyle(
                  color: Colors.white70,
                  letterSpacing: 1.1,
                  fontSize: 10,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Football. Predictions. Results.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 21,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Fixtures 鈥� Live scores 鈥� Match history',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        _section(
          'League tables',
          'Select one competition and load its latest standings',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedLeagueId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Competition',
                    prefixIcon: Icon(Icons.emoji_events_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: boomCompetitions.map((competition) {
                    return DropdownMenuItem<int>(
                      value: competition['id'] as int,
                      child: Text(
                        '${competition['name']} (${competition['country']})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: standingsLoading
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            selectedLeagueId = value;
                            standingsRows = [];
                            standingsError = null;
                          });
                        },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: selectedSeason,
                  decoration: const InputDecoration(
                    labelText: 'Table season',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [2026, 2025, 2024, 2023, 2022].map((year) =>
                    DropdownMenuItem<int>(
                      value: year,
                      child: Text(year.toString()),
                    )).toList(),
                  onChanged: standingsLoading ? null : (year) {
                    if (year == null) return;
                    setState(() {
                      selectedSeason = year;
                      standingsRows = [];
                      standingsError = null;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Season $selectedSeason 鈥� Table is loaded only when requested',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: standingsLoading ? null : _loadStandings,
                      icon: standingsLoading
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.table_chart_outlined, size: 17),
                      label: Text(
                        standingsLoading ? 'Loading' : 'Load table',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandRed,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        if (standingsError != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Table error: $standingsError',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],

        if (standingsRows.isNotEmpty) ...[
          const SizedBox(height: 10),
          _standingsTable(),
        ] else if (!standingsLoading && standingsError == null) ...[
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Choose a competition and tap 鈥淟oad table鈥�. '
                'Only that competition will be requested from API-Football.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
        ],

        const SizedBox(height: 18),
        _section(
          'Upcoming & recent fixtures',
          'Football data from API-Football',
        ),
        if (matches.isEmpty)
          _empty(
            'No fixtures loaded yet',
            'Pull down to refresh. If matches remain missing, check the API message above.',
          )
        else
          ...matches.map(_matchCard),
      ],
    ),
  );

  Widget _standingsTable() {
    final competition = boomCompetitions.firstWhere(
      (item) => item['id'] == selectedLeagueId,
      orElse: () => {'name': 'Football', 'country': ''},
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.emoji_events, color: brandRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${competition['name']} 鈥� ${competition['country']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '$selectedSeason',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              headingRowHeight: 42,
              dataRowMinHeight: 82,
              dataRowMaxHeight: 92,
              columns: const [
                DataColumn(label: Text('TEAM / FORM')),
                DataColumn(label: Text('MP')),
                DataColumn(label: Text('GD')),
                DataColumn(label: Text('PTS')),
              ],
              rows: standingsRows.map((row) {
                final rank = _standingsInt(row['rank']);
                final team = row['team'] as Map? ?? {};
                final all = row['all'] as Map? ?? {};
                final teamName = team['name']?.toString() ?? 'Team';
                final played = _standingsInt(all['played']);
                final wins = _standingsInt(all['win']);
                final draws = _standingsInt(all['draw']);
                final losses = _standingsInt(all['lose']);
                final goalsDiff = _standingsInt(row['goalsDiff']);
                final points = _standingsInt(row['points']);
                final form = row['form']?.toString() ?? '';

                return DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 245,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _teamLogo(team['logo']?.toString()),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    teamName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Win $wins   Draw $draws   Lost $losses',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Position $rank',
                              style: TextStyle(
                                color: _positionColor(rank),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (form.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              _formIndicators(form),
                            ],
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text('$played')),
                    DataCell(
                      Text(
                        goalsDiff > 0 ? '+$goalsDiff' : '$goalsDiff',
                        style: TextStyle(
                          color: goalsDiff > 0
                              ? Colors.green
                              : goalsDiff < 0
                                  ? Colors.red
                                  : null,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '$points',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Text(
              'W = Win 鈥� D = Draw 鈥� L = Lost. Position is shown in red beneath each team form. Last-five form is shown separately below when supplied by API-Football.',
              style: TextStyle(color: Colors.grey, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  int _standingsInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }


  int? _positionForTeam(dynamic teamId) {
    for (final row in standingsRows) {
      final team = row['team'] as Map? ?? {};
      if (team['id']?.toString() == teamId?.toString()) {
        final rank = int.tryParse(row['rank']?.toString() ?? '');
        if (rank != null && rank > 0) return rank;
      }
    }
    return null;
  }

  String _formForTeam(dynamic teamId) {
    for (final row in standingsRows) {
      final team = row['team'] as Map? ?? {};
      if (team['id']?.toString() == teamId?.toString()) {
        return row['form']?.toString() ?? '';
      }
    }
    return '';
  }

  Widget _teamSummary(String name, dynamic teamId, {bool alignEnd = false}) {
    final position = _positionForTeam(teamId);
    final form = _formForTeam(teamId);
    final alignment = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          position == null ? 'Position: load league table' : 'Position: $position',
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: position == null ? Colors.grey : _positionColor(position),
          ),
        ),
        if (form.isNotEmpty) ...[
          const SizedBox(height: 4),
          _formIndicators(form),
        ],
      ],
    );
  }

  Color _positionColor(int position) {
    if (position <= 3) return Colors.green;
    final teamCount = standingsRows.length;
    if (teamCount > 0 && position >= teamCount - 2) return Colors.red;
    return Colors.blue;
  }

  Widget _teamLogo(String? url) {
    if (url == null || url.isEmpty) {
      return const SizedBox(
        width: 25,
        height: 25,
        child: Icon(Icons.shield_outlined, size: 22, color: Colors.grey),
      );
    }
    return Image.network(
      url,
      width: 25,
      height: 25,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox(
        width: 25,
        height: 25,
        child: Icon(Icons.shield_outlined, size: 22, color: Colors.grey),
      ),
    );
  }

  Widget _formIndicators(String form) {
    final chars = form
        .toUpperCase()
        .split('')
        .where((c) => c == 'W' || c == 'D' || c == 'L')
        .toList();

    final lastFive = chars.length > 5
        ? chars.sublist(chars.length - 5)
        : chars;

    if (lastFive.isEmpty) {
      return const Text('鈥�', style: TextStyle(color: Colors.grey));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: lastFive.map((result) {
        final Color color;
        final String label;
        if (result == 'W') {
          color = Colors.green;
          label = 'W';
        } else if (result == 'D') {
          color = Colors.amber;
          label = 'D';
        } else {
          color = Colors.red;
          label = 'L';
        }

        return Container(
          width: 21,
          height: 21,
          margin: const EdgeInsets.only(right: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _livePage() => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(padding: const EdgeInsets.all(14), children: [
      _section('Live matches', 'Refresh to request the latest scores'),
      if (live.isEmpty) _empty('No live matches right now', 'Live fixtures appear here while matches are being played.')
      else ...live.map(_matchCard),
    ]),
  );
  Widget _picksPage() => ListView(padding: const EdgeInsets.all(14), children: [
    _section('BOOM Picks', 'Match information to support your own decisions'),
    const Card(child: Padding(padding:EdgeInsets.all(14), child: Text('Predictions are informational, not guarantees. This build does not claim to use a trained AI model. Match tips will be expanded when verified statistics and prediction logic are connected.'))),
    if (matches.isEmpty) _empty('No fixtures available', 'Load fixtures to see match cards.')
    else ...matches.map((m) {
      final teams = m['teams'] as Map? ?? {};
      final h = teams['home'] as Map? ?? {};
      final a = teams['away'] as Map? ?? {};
      return Card(child: ListTile(leading: const Icon(Icons.auto_awesome,color:brandRed), title: Text('${h['name'] ?? 'Home'} vs ${a['name'] ?? 'Away'}'), subtitle: Text((m['league'] as Map?)?['name']?.toString() ?? 'Football'), trailing: const Text('Analysis',style:TextStyle(color:brandRed))));
    }),
  ]);
  Widget _historyPage() => ListView(padding: const EdgeInsets.all(14), children: [
    _section('Match History', 'Matches you chose to save on this device'),
    if (history.isEmpty) _empty('Your history is empty', 'Open a match and tap Save to History to keep it here.')
    else ...history.map((m) => Card(child: ListTile(leading: const Icon(Icons.history,color:brandRed), title: Text('${m['home']} vs ${m['away']}'), subtitle: Text('${m['league']} 鈥� ${m['score']}'), trailing: IconButton(icon:const Icon(Icons.delete_outline),onPressed:() async { history.remove(m); await LocalStore.write(LocalStore.historyKey,history); setState((){}); })))),
  ]);
  Widget _notificationsPage() => ListView(padding: const EdgeInsets.all(14), children: [
    _section('Notifications', 'BOOM app updates and saved alerts'),
    SwitchListTile(
      secondary: Icon(
        notificationsEnabled ? Icons.notifications_active : Icons.notifications_off,
        color: brandRed,
      ),
      value: notificationsEnabled,
      onChanged: (v) {
        setState(() => notificationsEnabled = v);
        _addNotice(
          'Notification setting changed',
          v ? 'In-app alerts enabled.' : 'In-app alerts paused.',
        );
      },
      title: const Text('In-app notifications'),
      subtitle: const Text('Controls alerts shown inside this app. Push notifications require a later Firebase setup.'),
    ),
    SwitchListTile(
      secondary: Icon(
        notificationSoundEnabled ? Icons.volume_up : Icons.volume_off,
        color: notificationSoundEnabled ? brandRed : Colors.grey,
      ),
      value: notificationSoundEnabled,
      onChanged: _setNotificationSound,
      title: Text(notificationSoundEnabled ? 'Sound ON' : 'Sound OFF'),
      subtitle: Text(
        notificationSoundEnabled
            ? 'Notification sound is enabled.'
            : 'Notification sound is disabled.',
      ),
    ),
    if (notices.isEmpty) _empty('No notifications yet', 'Important in-app messages will appear here.')
    else ...notices.map((n)=>Card(child:ListTile(leading:const Icon(Icons.notifications_active_outlined,color:brandRed),title:Text(n['title']??''),subtitle:Text(n['message']??'')))),
    TextButton(onPressed:() async { notices.clear(); await LocalStore.write(LocalStore.noticeKey,notices); setState((){}); }, child:const Text('Clear notifications')),
  ]);
  Widget _proPage() => ListView(padding: const EdgeInsets.all(14), children: [
    _section('BOOM Pro', 'Premium subscription'),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Icon(Icons.workspace_premium,color:brandRed,size:42),
      const SizedBox(height:10), const Text('BOOM PRO',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
      const Text('鈧�2,000 / month',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold,color:brandRed)),
      const SizedBox(height:8), const Text('Existing Paystack plan reference: PLN_dx1vkqqoydbnsqe'),
      const SizedBox(height:8), const Text('Checkout and subscription verification must be reconnected to the existing secure Supabase Edge Function before payments can be accepted. No payment is taken in this upgrade preview.'),
      const SizedBox(height:12), const Chip(label:Text('Payment connection pending verification')),
    ]))),
  ]);
  Widget _accountPage() => ListView(padding: const EdgeInsets.all(14), children: [
    Center(child:Column(children:[
      ClipRRect(borderRadius:BorderRadius.circular(18),child:Image.asset('assets/boom_logo.png',width:90,height:90,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.sports_soccer,size:70))),
      const SizedBox(height:8), const Text('BOOMGRATULATIONS',style:TextStyle(fontWeight:FontWeight.w900,fontSize:19)),
    ])),
    const SizedBox(height:18),
    _info('Football data', apiKey.isEmpty ? 'API-Football key not supplied in this build.' : 'API-Football key supplied.'),
    _info('Supabase', supabaseInitialized ? 'Connected to the existing Supabase project.' : 'Not connected in this build. The app remains usable without account sync.'),
    _info('Backend project', supabaseUrl),
    _info('Data safety', 'This upgrade does not alter your existing Supabase tables or records.'),
    if (supabaseInitialized) _info('Authentication', 'Supabase client initialized. Sign-in and profile sync are the next integration stage.'),
  ]);
  Widget _section(String title,String subtitle)=>Padding(padding:const EdgeInsets.only(bottom:10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18)),Text(subtitle,style:const TextStyle(color:Colors.grey,fontSize:11))]));
  Widget _empty(String title,String body)=>Padding(padding:const EdgeInsets.symmetric(vertical:35),child:Column(children:[const Icon(Icons.sports_soccer_outlined,size:42,color:Colors.grey),const SizedBox(height:8),Text(title,style:const TextStyle(fontWeight:FontWeight.bold)),Text(body,textAlign:TextAlign.center,style:const TextStyle(color:Colors.grey,fontSize:12))]));
  Widget _info(String title,String body)=>Card(child:ListTile(leading:const Icon(Icons.info_outline,color:brandRed),title:Text(title),subtitle:Text(body)));
  String _formatKickoff(String raw) {
    if (raw.isEmpty) return 'Kick-off time unavailable';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year} $hour:$minute';
  }
  Widget _matchCard(Map<String,dynamic> m) {
    final f = m['fixture'] as Map? ?? {};
    final teams = m['teams'] as Map? ?? {};
    final h = teams['home'] as Map? ?? {};
    final a = teams['away'] as Map? ?? {};
    final goals = m['goals'] as Map? ?? {};
    final league = m['league'] as Map? ?? {};
    final status = f['status'] as Map? ?? {};
    final venue = f['venue'] as Map? ?? {};

    final score = (goals['home'] == null && goals['away'] == null)
        ? 'VS'
        : '${goals['home']} - ${goals['away']}';
    final short = (status['short'] ?? 'NS').toString();
    final venueName = venue['name']?.toString().trim() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MatchInsightsPage(
            match: m,
            standingsRows: standingsRows,
          ),
        )),
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${league['name'] ?? 'Football'} 鈥� ${league['country'] ?? ''}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                    ),
                  ),
                ),
                Text(
                  short,
                  style: const TextStyle(
                    color: brandRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _teamSummary(
                    h['name']?.toString() ?? 'Home',
                    h['id'],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    score,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Expanded(
                  child: _teamSummary(
                    a['name']?.toString() ?? 'Away',
                    a['id'],
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            if (venueName.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(
                    Icons.stadium_outlined,
                    size: 14,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      venueName,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatKickoff(f['date']?.toString() ?? ''),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _saveHistory(m),
                  icon: const Icon(
                    Icons.bookmark_add_outlined,
                    size: 16,
                  ),
                  label: const Text('Save to History'),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}


class MatchInsightsPage extends StatefulWidget {
  const MatchInsightsPage({
    super.key,
    required this.match,
    required this.standingsRows,
  });

  final Map<String, dynamic> match;
  final List<Map<String, dynamic>> standingsRows;

  @override
  State<MatchInsightsPage> createState() => _MatchInsightsPageState();
}

class _MatchInsightsPageState extends State<MatchInsightsPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> homeRecent = [];
  List<Map<String, dynamic>> awayRecent = [];
  List<Map<String, dynamic>> h2h = [];
  List<Map<String, dynamic>> statistics = [];

  Map? get _teams => widget.match['teams'] as Map?;
  Map? get _home => _teams?['home'] as Map?;
  Map? get _away => _teams?['away'] as Map?;
  Map? get _fixture => widget.match['fixture'] as Map?;
  Map? get _league => widget.match['league'] as Map?;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    final homeId = _home?['id']?.toString();
    final awayId = _away?['id']?.toString();
    final fixtureId = _fixture?['id']?.toString();
    final season = _league?['season']?.toString() ??
        DateTime.now().year.toString();
    if (homeId == null || awayId == null) {
      setState(() {
        loading = false;
        error = 'Team identifiers are missing from this fixture.';
      });
      return;
    }
    try {
      final api = FootballApi();
      final results = await Future.wait([
        api.endpoint('fixtures', {
          'team': homeId, 'last': '5', 'season': season,
          'timezone': 'Africa/Lagos',
        }),
        api.endpoint('fixtures', {
          'team': awayId, 'last': '5', 'season': season,
          'timezone': 'Africa/Lagos',
        }),
        api.endpoint('fixtures/headtohead', {
          'h2h': '$homeId-$awayId', 'last': '5',
          'timezone': 'Africa/Lagos',
        }),
        if (fixtureId != null)
          api.endpoint('fixtures/statistics', {'fixture': fixtureId})
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        homeRecent = results[0];
        awayRecent = results[1];
        h2h = results[2];
        statistics = results[3];
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = widget.match['goals'] as Map? ?? {};
    final homeName = _home?['name']?.toString() ?? 'Home';
    final awayName = _away?['name']?.toString() ?? 'Away';
    final score = goals['home'] == null && goals['away'] == null
        ? 'VS'
        : '${goals['home']} - ${goals['away']}';
    return Scaffold(
      appBar: AppBar(title: const Text('Match analysis')),
      body: RefreshIndicator(
        onRefresh: _loadInsights,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(_league?['name']?.toString() ?? 'Football',
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text(homeName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(score,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    ),
                    Expanded(child: Text(awayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 8),
                  Text(_fixture?['date']?.toString() ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ]),
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Card(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Some analysis data could not be loaded: $error'),
              )),
            _sectionTitle('Last five matches'),
            _recentCard(homeName, _home?['id']?.toString(), homeRecent),
            _recentCard(awayName, _away?['id']?.toString(), awayRecent),
            _sectionTitle('Head-to-head 鈥� last five meetings'),
            _h2hCard(homeName, awayName),
            _sectionTitle('Match statistics'),
            _statisticsCard(homeName, awayName),
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                'W = Win, D = Draw, L = Lost. Statistics are shown only when supplied by API-Football. A match that has not started may not have statistics yet.',
                style: TextStyle(color: Colors.grey, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 2, 7),
    child: Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
  );

  Widget _recentCard(String teamName, String? teamId, List<Map<String, dynamic>> games) {
    if (games.isEmpty) {
      return Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text('$teamName: recent form unavailable.'),
      ));
    }
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(teamName, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 5, runSpacing: 5, children: games.map((game) {
          final teams = game['teams'] as Map? ?? {};
          final home = teams['home'] as Map? ?? {};
          final away = teams['away'] as Map? ?? {};
          final goals = game['goals'] as Map? ?? {};
          final isHome = home['id']?.toString() == teamId;
          final own = isHome ? goals['home'] : goals['away'];
          final opp = isHome ? goals['away'] : goals['home'];
          final result = own == null || opp == null
              ? '?' : (own > opp ? 'W' : own < opp ? 'L' : 'D');
          return _resultBox(result, expanded: true);
        }).toList()),
        const SizedBox(height: 8),
        ...games.map((game) {
          final teams = game['teams'] as Map? ?? {};
          final home = teams['home'] as Map? ?? {};
          final away = teams['away'] as Map? ?? {};
          final goals = game['goals'] as Map? ?? {};
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${home['name'] ?? 'Home'} ${goals['home'] ?? '-'} - ${goals['away'] ?? '-'} ${away['name'] ?? 'Away'}',
              style: const TextStyle(fontSize: 11),
            ),
          );
        }),
      ]),
    ));
  }

  Widget _resultBox(String result, {bool expanded = false}) {
    final color = result == 'W' ? Colors.green : result == 'D'
        ? Colors.orange : result == 'L' ? Colors.red : Colors.grey;
    return Container(
      width: expanded ? 30 : null,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(result, style: const TextStyle(
        color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12,
      )),
    );
  }

  Widget _h2hCard(String homeName, String awayName) {
    if (h2h.isEmpty) {
      return const Card(child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('No head-to-head records returned by the football data provider.'),
      ));
    }
    var homeWins = 0, draws = 0, awayWins = 0;
    for (final game in h2h) {
      final teams = game['teams'] as Map? ?? {};
      final goals = game['goals'] as Map? ?? {};
      final homeId = _home?['id']?.toString();
      final homeGoals = goals['home'];
      final awayGoals = goals['away'];
      if (homeGoals == null || awayGoals == null) continue;
      final winner = homeGoals > awayGoals
          ? (teams['home']?['id']?.toString() == homeId ? 'home' : 'away')
          : homeGoals < awayGoals
              ? (teams['away']?['id']?.toString() == homeId ? 'home' : 'away')
              : 'draw';
      if (winner == 'home') homeWins++;
      else if (winner == 'away') awayWins++;
      else draws++;
    }
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Expanded(child: Column(children: [
            Text(homeName, textAlign: TextAlign.center),
            Text('$homeWins wins', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900)),
          ])),
          const Text('|'),
          Expanded(child: Column(children: [
            const Text('Draws'),
            Text('$draws', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w900)),
          ])),
          const Text('|'),
          Expanded(child: Column(children: [
            Text(awayName, textAlign: TextAlign.center),
            Text('$awayWins wins', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900)),
          ])),
        ]),
        const Divider(),
        ...h2h.map((game) {
          final teams = game['teams'] as Map? ?? {};
          final home = teams['home'] as Map? ?? {};
          final away = teams['away'] as Map? ?? {};
          final goals = game['goals'] as Map? ?? {};
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${home['name'] ?? ''} ${goals['home'] ?? '-'} - ${goals['away'] ?? '-'} ${away['name'] ?? ''}',
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
            ),
          );
        }),
      ]),
    ));
  }

  Widget _statisticsCard(String homeName, String awayName) {
    if (statistics.isEmpty) {
      return const Card(child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('Match statistics are not available yet. They are normally returned after kick-off.'),
      ));
    }
    final byTeam = <String, Map<String, dynamic>>{};
    for (final entry in statistics) {
      final team = entry['team'] as Map? ?? {};
      final values = entry['statistics'] as List? ?? [];
      final map = <String, dynamic>{};
      for (final item in values) {
        if (item is Map && item['type'] != null) {
          map[item['type'].toString()] = item['value'];
        }
      }
      byTeam[team['id']?.toString() ?? ''] = map;
    }
    final homeStats = byTeam[_home?['id']?.toString()] ?? {};
    final awayStats = byTeam[_away?['id']?.toString()] ?? {};
    final keys = <String>[
      'Ball Possession', 'Total Shots', 'Shots on Goal', 'Shots off Goal',
      'Corner Kicks', 'Fouls', 'Yellow Cards', 'Red Cards', 'Offsides',
      'Goalkeeper Saves', 'Total passes', 'Passes %',
    ];
    final rows = keys.where((key) =>
      homeStats.containsKey(key) || awayStats.containsKey(key)).toList();
    if (rows.isEmpty) {
      return const Card(child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('The provider has not supplied detailed statistics for this fixture.'),
      ));
    }
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(homeName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
          const Expanded(child: Text('STAT', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 10))),
          Expanded(child: Text(awayName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const Divider(),
        ...rows.map((key) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text('${homeStats[key] ?? '-'}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
            Expanded(child: Text(key, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey))),
            Expanded(child: Text('${awayStats[key] ?? '-'}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
        )),
      ]),
    ));
  }
}
