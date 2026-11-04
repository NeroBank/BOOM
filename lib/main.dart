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

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _refresh();
  }
  Future<void> _loadLocal() async {
    final h = await LocalStore.read(LocalStore.historyKey);
    final n = await LocalStore.read(LocalStore.noticeKey);
    if (mounted) setState(() { history = h; notices = n; });
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
    child: ListView(padding: const EdgeInsets.all(14), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors:[brandRed,Color(0xFF7F0000)]), borderRadius: BorderRadius.circular(18)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
        Text('YOUR FOOTBALL CENTRE', style: TextStyle(color:Colors.white70,letterSpacing:1.1,fontSize:10)),
        SizedBox(height:8), Text('Football. Predictions. Results.', style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:21)),
        SizedBox(height:6), Text('Fixtures 鈥� Live scores 鈥� Match history',style:TextStyle(color:Colors.white70,fontSize:11)),
      ])),
      const SizedBox(height:18),
      _section('Upcoming & recent fixtures', 'Football data from API-Football'),
      if (matches.isEmpty) _empty('No fixtures loaded yet', 'Pull down to refresh. If matches remain missing, check the API message above.')
      else ...matches.map(_matchCard),
    ]),
  );
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
    SwitchListTile(value: notificationsEnabled, onChanged: (v) { setState(()=>notificationsEnabled=v); _addNotice('Notification setting changed', v ? 'In-app alerts enabled.' : 'In-app alerts paused.'); }, title: const Text('In-app notifications'), subtitle: const Text('Controls alerts shown inside this app. Push notifications require a later Firebase setup.')),
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
    final f=m['fixture'] as Map? ?? {}; final teams=m['teams'] as Map? ?? {};
    final h=teams['home'] as Map? ?? {}; final a=teams['away'] as Map? ?? {};
    final goals=m['goals'] as Map? ?? {}; final league=m['league'] as Map? ?? {};
    final status=f['status'] as Map? ?? {};
    final score=(goals['home']==null && goals['away']==null)?'VS':'${goals['home']} - ${goals['away']}';
    final short=(status['short']??'NS').toString();
    return Card(margin:const EdgeInsets.only(bottom:9),child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Row(children:[Expanded(child:Text('${league['name']??'Football'} 鈥� ${league['country']??''}',style:const TextStyle(color:Colors.grey,fontSize:10))),Text(short,style:const TextStyle(color:brandRed,fontWeight:FontWeight.bold,fontSize:11))]),
      const SizedBox(height:10),
      Row(children:[Expanded(child:Text(h['name']??'Home',style:const TextStyle(fontWeight:FontWeight.bold),maxLines:2)),Text(score,style:const TextStyle(fontWeight:FontWeight.w900)),Expanded(child:Text(a['name']??'Away',textAlign:TextAlign.end,style:const TextStyle(fontWeight:FontWeight.bold),maxLines:2))]),
      const SizedBox(height:7),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Text(_formatKickoff(f['date']?.toString() ?? ''),style:const TextStyle(color:Colors.grey,fontSize:10)),
        TextButton.icon(onPressed:()=>_saveHistory(m),icon:const Icon(Icons.bookmark_add_outlined,size:16),label:const Text('Save to History')),
      ]),
    ])));
  }
}
