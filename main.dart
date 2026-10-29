import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiKey = String.fromEnvironment('API_FOOTBALL_KEY');
const apiBase = 'https://v3.football.api-sports.io';

void main() => runApp(const BoomgratulationsApp());

class BoomgratulationsApp extends StatelessWidget {
  const BoomgratulationsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BOOMGRATULATIONS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD50000)),
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        fontFamily: 'Times New Roman',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFD50000),
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class MatchItem {
  final String country, league, badge, home, away, stadium, time, score;
  final int homePos, awayPos;
  final String homeForm, awayForm;
  final List<String> odds;
  final bool live;
  final String status, market, pick, pickOdds;

  const MatchItem({
    required this.country, required this.league, required this.badge,
    required this.home, required this.away, required this.stadium,
    required this.time, required this.score, required this.homePos,
    required this.awayPos, required this.homeForm, required this.awayForm,
    required this.odds, this.live = false, this.status = 'NS', this.market = 'Over 1.5 Goals',
    this.pick = 'WIN', this.pickOdds = '1.42',
  });
}

const demoMatches = <MatchItem>[
  MatchItem(country:'England', league:'Premier League', badge:'🏴', home:'Arsenal', away:'Chelsea', stadium:'Emirates Stadium', time:'15:00', score:'vs', homePos:2, awayPos:7, homeForm:'WWDWW', awayForm:'WLWDW', odds:['1.92','3.55','4.10'], market:'Over 1.5 Goals', pick:'WIN', pickOdds:'1.28'),
  MatchItem(country:'England', league:'Premier League', badge:'🏴', home:'Man City', away:'Aston Villa', stadium:'Etihad Stadium', time:'17:30', score:'vs', homePos:1, awayPos:8, homeForm:'WWWWW', awayForm:'WDLWW', odds:['1.48','4.50','6.80'], market:'Both Teams to Score', pick:'WIN', pickOdds:'1.66'),
  MatchItem(country:'Germany', league:'Bundesliga', badge:'🇩🇪', home:'Bayern Munich', away:'Freiburg', stadium:'Allianz Arena', time:'14:30', score:'vs', homePos:1, awayPos:11, homeForm:'WWDWW', awayForm:'LDWWL', odds:['1.30','5.60','8.20'], market:'Over 2.5 Goals', pick:'WIN', pickOdds:'1.51'),
  MatchItem(country:'Italy', league:'Serie A', badge:'🇮🇹', home:'AC Milan', away:'Inter Milan', stadium:'San Siro', time:'19:45', score:'vs', homePos:4, awayPos:3, homeForm:'WDWWL', awayForm:'WWDWW', odds:['2.65','3.20','2.55'], market:'Draw', pick:'DRAW', pickOdds:'3.20'),
  MatchItem(country:'Spain', league:'La Liga', badge:'🇪🇸', home:'Real Madrid', away:'Barcelona', stadium:'Santiago Bernabéu', time:'20:00', score:'vs', homePos:1, awayPos:2, homeForm:'WWWWW', awayForm:'WWDWW', odds:['2.10','3.60','3.10'], market:'Over 2.5 Goals', pick:'WIN', pickOdds:'1.74'),
  MatchItem(country:'France', league:'Ligue 1', badge:'🇫🇷', home:'Marseille', away:'Lyon', stadium:'Orange Vélodrome', time:'20:00', score:'vs', homePos:6, awayPos:16, homeForm:'WDLWW', awayForm:'LLDWL', odds:['1.85','3.65','4.00'], market:'Home or Draw', pick:'WIN', pickOdds:'1.35'),
  MatchItem(country:'Portugal', league:'Primeira Liga', badge:'🇵🇹', home:'Benfica', away:'Porto', stadium:'Estádio da Luz', time:'21:15', score:'vs', homePos:2, awayPos:3, homeForm:'WWDWW', awayForm:'WWWLW', odds:['2.05','3.30','3.45'], market:'Both Teams to Score', pick:'DRAW', pickOdds:'3.30'),
];

class FootballApi {
  static const _headers = {'x-apisports-key': apiKey};
  static final Map<String, Map<int, int>> _positionCache = {};

  static Future<Map<String, dynamic>> _get(String path, [Map<String, String>? params]) async {
    final uri = Uri.parse('$apiBase/$path').replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('API-Football returned HTTP ${response.statusCode} for $path');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) throw Exception('Unexpected API response for $path');
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      throw Exception('API-Football: ${errors.values.join(', ')}');
    }
    return body;
  }

  static String _text(dynamic value, [String fallback = '']) =>
      value == null || value.toString().trim().isEmpty ? fallback : value.toString();

  static int _int(dynamic value, [int fallback = 0]) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? fallback;

  static String _flag(String country) {
    const flags = {
      'England':'🏴','Scotland':'🏴','Wales':'🏴','Northern Ireland':'🇬🇧',
      'Spain':'🇪🇸','Italy':'🇮🇹','Germany':'🇩🇪','France':'🇫🇷',
      'Portugal':'🇵🇹','Netherlands':'🇳🇱','Belgium':'🇧🇪','Nigeria':'🇳🇬',
      'Turkey':'🇹🇷','Türkiye':'🇹🇷','Saudi Arabia':'🇸🇦','Brazil':'🇧🇷',
      'Argentina':'🇦🇷','United States':'🇺🇸','USA':'🇺🇸','Japan':'🇯🇵',
      'International':'🌍',
    };
    return flags[country] ?? '🌍';
  }

  static Future<Map<int, int>> _positions(int leagueId, int season) async {
    final key = '$leagueId-$season';
    if (_positionCache.containsKey(key)) return _positionCache[key]!;
    try {
      final json = await _get('standings', {'league': '$leagueId', 'season': '$season'});
      final result = <int, int>{};
      final response = json['response'];
      if (response is List && response.isNotEmpty) {
        final league = response.first['league'];
        final tables = league is Map ? league['standings'] : null;
        if (tables is List) {
          for (final group in tables) {
            if (group is List) {
              for (final row in group) {
                if (row is Map) {
                  final team = row['team'];
                  if (team is Map) result[_int(team['id'])] = _int(row['rank']);
                }
              }
            }
          }
        }
      }
      _positionCache[key] = result;
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<Map<int, Map<String, String>>> _oddsForDate(String date) async {
    final result = <int, Map<String, String>>{};
    try {
      final json = await _get('odds', {'date': date});
      final rows = json['response'];
      if (rows is! List) return result;
      for (final row in rows) {
        if (row is! Map) continue;
        final fixture = row['fixture'];
        if (fixture is! Map) continue;
        final id = _int(fixture['id']);
        String? home, draw, away;
        final books = row['bookmakers'];
        if (books is List) {
          for (final book in books) {
            final bets = book is Map ? book['bets'] : null;
            if (bets is! List) continue;
            for (final bet in bets) {
              if (bet is! Map) continue;
              final name = _text(bet['name']).toLowerCase();
              if (!(name.contains('match winner') || name == '1x2' || name == 'fulltime result')) continue;
              final values = bet['values'];
              if (values is! List) continue;
              for (final value in values) {
                if (value is! Map) continue;
                final label = _text(value['value']).toLowerCase();
                final odd = _text(value['odd']);
                if (label == 'home' || label == '1') home ??= odd;
                if (label == 'draw' || label == 'x') draw ??= odd;
                if (label == 'away' || label == '2') away ??= odd;
              }
              if (home != null || draw != null || away != null) break;
            }
            if (home != null || draw != null || away != null) break;
          }
        }
        if (home != null || draw != null || away != null) {
          result[id] = {'1': home ?? '—', 'X': draw ?? '—', '2': away ?? '—'};
        }
      }
    } catch (_) {
      // Odds coverage depends on the user's API plan and the competition.
    }
    return result;
  }

  static Future<List<MatchItem>> fetchFixtures({String mode = 'fixtures'}) async {
    if (apiKey.isEmpty) throw Exception('Missing API_FOOTBALL_KEY. Add it in GitHub Actions secrets.');
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final params = <String, String>{'timezone': 'Africa/Lagos'};
    if (mode == 'live') {
      params['live'] = 'all';
    } else if (mode == 'results') {
      params['last'] = '50';
      params['status'] = 'FT-AET-PEN';
    } else {
      params['date'] = date;
    }

    final json = await _get('fixtures', params);
    final rows = json['response'];
    if (rows is! List) return <MatchItem>[];

    final rawRows = rows.whereType<Map>().toList();
    final leagueIds = <int>{};
    for (final row in rawRows) {
      final league = row['league'];
      if (league is Map) {
        final id = _int(league['id']);
        if (id > 0) leagueIds.add(id);
      }
    }

    final positionMaps = <int, Map<int, int>>{};
    await Future.wait(leagueIds.map((id) async {
      final row = rawRows.firstWhere((r) => r['league'] is Map && _int(r['league']['id']) == id);
      final league = row['league'] as Map;
      final season = _int(league['season'], now.year);
      positionMaps[id] = await _positions(id, season);
    }));

    final odds = mode == 'live' ? <int, Map<String, String>>{} : await _oddsForDate(date);
    final matches = <MatchItem>[];
    for (final row in rawRows) {
      final fixture = row['fixture'] is Map ? row['fixture'] as Map : {};
      final league = row['league'] is Map ? row['league'] as Map : {};
      final teams = row['teams'] is Map ? row['teams'] as Map : {};
      final home = teams['home'] is Map ? teams['home'] as Map : {};
      final away = teams['away'] is Map ? teams['away'] as Map : {};
      final goals = row['goals'] is Map ? row['goals'] as Map : {};
      final venue = fixture['venue'] is Map ? fixture['venue'] as Map : {};
      final statusMap = fixture['status'] is Map ? fixture['status'] as Map : {};
      final country = _text(league['country'], 'International');
      final leagueId = _int(league['id']);
      final pos = positionMaps[leagueId] ?? {};
      final homeId = _int(home['id']);
      final awayId = _int(away['id']);
      final status = _text(statusMap['short'], 'NS');
      final isLive = ['1H','HT','2H','ET','BT','P','LIVE','INT'].contains(status);
      final rawDate = _text(fixture['date']);
      final dateValue = DateTime.tryParse(rawDate);
      final time = dateValue == null
          ? 'TBD'
          : '${rawDate.length >= 16 ? rawDate.substring(11, 13) : dateValue.hour.toString().padLeft(2, '0')}:${rawDate.length >= 16 ? rawDate.substring(14, 16) : dateValue.minute.toString().padLeft(2, '0')}';
      final isFinished = ['FT','AET','PEN'].contains(status);
      final score = isFinished || isLive
          ? '${_text(goals['home'], '0')} - ${_text(goals['away'], '0')}'
          : 'vs';
      final matchOdds = odds[_int(fixture['id'])] ?? const {'1':'—','X':'—','2':'—'};
      final formHome = _text(pos[homeId], '—');
      final formAway = _text(pos[awayId], '—');
      matches.add(MatchItem(
        country: country,
        league: _text(league['name'], 'Football'),
        badge: _flag(country),
        home: _text(home['name'], 'Home'),
        away: _text(away['name'], 'Away'),
        stadium: _text(venue['name'], 'Stadium not listed'),
        time: isLive ? '${_text(statusMap['elapsed'], '')}${statusMap['elapsed'] == null ? '' : "'"} LIVE' : time,
        score: score,
        homePos: int.tryParse(formHome) ?? 0,
        awayPos: int.tryParse(formAway) ?? 0,
        homeForm: '',
        awayForm: '',
        odds: [matchOdds['1'] ?? '—', matchOdds['X'] ?? '—', matchOdds['2'] ?? '—'],
        live: isLive,
        status: status,
        market: 'Match Winner',
        pick: 'INFO',
        pickOdds: '—',
      ));
    }
    matches.sort((a, b) {
      final countryCompare = a.country.compareTo(b.country);
      if (countryCompare != 0) return countryCompare;
      return a.time.compareTo(b.time);
    });
    return matches;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  String country = 'All';
  bool loading = false;
  List<MatchItem> matches = demoMatches;
  final countries = const ['All','England','France','Germany','Italy','Portugal','Spain'];

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final mode = tab == 1 ? 'live' : (tab == 3 ? 'results' : 'fixtures');
      final result = await FootballApi.fetchFixtures(mode: mode);
      if (!mounted) return;
      setState(() {
        matches = result;
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Loaded ${result.length} matches from API-Football.'),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not load API data: $e'),
        duration: const Duration(seconds: 5),
      ));
    }
  }

  @override
  void initState() {
    super.initState();
    if (apiKey.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Fixtures','Live','Picks','Results','Account'];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: const Center(child: Text('⚽', style: TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 9),
          const Expanded(child: Text('BOOMGRATULATIONS',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: .2))),
        ]),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: tab == 4 ? const AccountPage() : Column(children: [
        _topTabs(titles),
        if (tab == 0 || tab == 1) _countryPicker(),
        Expanded(child: loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD50000)))
          : _content()),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFFFDADA),
        onDestinationSelected: (v) { setState(() => tab = v); if (v != 4 && apiKey.isNotEmpty) _refresh(); },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label:'Fixtures'),
          NavigationDestination(icon: Icon(Icons.sensors), selectedIcon: Icon(Icons.sensors), label:'Live'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), selectedIcon: Icon(Icons.auto_awesome), label:'Picks'),
          NavigationDestination(icon: Icon(Icons.scoreboard_outlined), selectedIcon: Icon(Icons.scoreboard), label:'Results'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label:'Account'),
        ],
      ),
    );
  }

  Widget _topTabs(List<String> titles) => Container(
    color: const Color(0xFFB80000),
    child: Row(children: List.generate(4, (i) => Expanded(child: InkWell(
      onTap: () { setState(() => tab = i); if (apiKey.isNotEmpty) _refresh(); },
      child: Container(padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(
          color: tab == i ? Colors.white : Colors.transparent, width: 2.5))),
        child: Text(titles[i], textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 12,
            fontWeight: tab == i ? FontWeight.bold : FontWeight.normal)),
      ),
    )))),
  );

  Widget _countryPicker() => Container(
    color: Colors.white,
    height: 44,
    child: ListView(scrollDirection: Axis.horizontal, children: countries.map((c) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: ChoiceChip(label: Text(c, style: const TextStyle(fontSize: 11)),
          selected: country == c, selectedColor: const Color(0xFFFFDADA),
          onSelected: (_) => setState(() => country = c),
          visualDensity: VisualDensity.compact, side: BorderSide.none,
        ))).toList(),
    ),
  );

  Widget _content() {
    var visible = matches.where((m) => country == 'All' || m.country == country).toList();
    visible.sort((a,b) => a.country.compareTo(b.country));
    if (tab == 1) {
      visible = visible.where((m) => m.live).toList();
    }
    if (tab == 2) {
      return ListView(children: [
      _sectionTitle('🔥 TODAY’S PICKS', 'Tips are informational, not guarantees'),
      ...matches.map((m) => _pickCard(m)),
      ]);
    }
    if (tab == 3) {
      return ListView(children: [
      _sectionTitle('📋 RECENT RESULTS', apiKey.isEmpty ? 'Illustrative sample scores — configure API key for real results' : 'Recent completed fixtures from API-Football'),
      if (apiKey.isEmpty) ...[
        _resultRow('Real Madrid', '2 - 1', 'Barcelona', 'WIN'),
        _resultRow('Arsenal', '1 - 1', 'Chelsea', 'DRAW'),
        _resultRow('AC Milan', '0 - 2', 'Inter Milan', 'LOST'),
      ] else ...visible.map((m) {
        final parts = m.score.split(' - ');
        final h = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
        final a = parts.length > 1 ? int.tryParse(parts[1]) : null;
        final outcome = h == null || a == null ? 'FT' : (h == a ? 'DRAW' : (h > a ? 'WIN' : 'LOST'));
        return _resultRow(m.home, m.score, m.away, outcome);
      }),
      if (apiKey.isNotEmpty && visible.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('No recent finished matches returned by the provider.', style: TextStyle(color: Colors.black54, fontSize: 11))),
      ]);
    }
    if (tab == 1 && visible.isEmpty) {
      return const Center(child: Text('No live matches in this demo feed.'));
    }
    return ListView(children: [
      if (tab == 1) _sectionTitle('🔴 LIVE MATCHES', 'Live feed requires a configured API key'),
      ...visible.map(_matchCard),
    ]);
  }

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 7),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFB80000))),
      Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.black54)),
    ]),
  );

  Widget _matchCard(MatchItem m) => Card(
    margin: const EdgeInsets.fromLTRB(10, 5, 10, 5), elevation: 0,
    color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
      Row(children: [
        Text(m.badge, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 5),
        Expanded(child: Text('${m.league} · ${m.country}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        Text(m.time, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB80000))),
      ]),
      const Divider(height: 13),
      Row(children: [
        _position(m.homePos),
        const SizedBox(width: 5),
        Expanded(child: Text(m.home, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        Text(m.score, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        Expanded(child: Text(m.away, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        const SizedBox(width: 5),
        _position(m.awayPos),
        const SizedBox(width: 8),
        Column(children: [
          _formDot(m.homeForm),
          const SizedBox(height: 3),
          _formDot(m.awayForm),
        ]),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        const Icon(Icons.stadium_outlined, size: 13, color: Colors.black54),
        const SizedBox(width: 4),
        Expanded(child: Text(m.stadium, style: const TextStyle(fontSize: 10, color: Colors.black54))),
        const Icon(Icons.public, size: 12, color: Colors.black45),
        const SizedBox(width: 3),
        Text(m.country, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _oddsChip('1', m.odds[0]), _oddsChip('X', m.odds[1]), _oddsChip('2', m.odds[2]),
        const Spacer(),
        Text('W', style: TextStyle(color: _formColor(m.homeForm), fontSize: 10, fontWeight: FontWeight.bold)),
        const Text('  D  ', style: TextStyle(color: Color(0xFFE0A800), fontSize: 10, fontWeight: FontWeight.bold)),
        const Text('L', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
    ])),
  );

  Widget _position(int p) {
    if (p <= 0) return Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(6)), child: const Text('—', style: TextStyle(color: Colors.white, fontSize: 11)));
    final Color c = p <= 3 ? const Color(0xFF159447) : (p >= 16 ? const Color(0xFFD50000) : const Color(0xFF1769D2));
    return Container(width: 22, height: 22, alignment: Alignment.center,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
      child: Text('$p${p >= 16 ? '😢' : ''}', style: TextStyle(color: Colors.white, fontSize: p >= 16 ? 8 : 11, fontWeight: FontWeight.bold)));
  }

  Color _formColor(String form) => form.startsWith('W') ? Colors.green : Colors.red;
  Widget _formDot(String form) {
    final last = form.isNotEmpty ? form[0] : '-';
    final color = last == 'W' ? Colors.green : (last == 'D' ? const Color(0xFFE0A800) : Colors.red);
    return Container(width: 20, height: 16, alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(last, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)));
  }

  Widget _oddsChip(String label, String value) => Expanded(child: Container(
    margin: const EdgeInsets.only(right: 4), padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFFF2F4F7), borderRadius: BorderRadius.circular(6)),
    child: Text('$label  $value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
  ));

  Widget _pickCard(MatchItem m) => Card(
    margin: const EdgeInsets.fromLTRB(10, 5, 10, 5), elevation: 0,
    child: ListTile(
      leading: CircleAvatar(backgroundColor: const Color(0xFFFFE2E2), child: Text(m.badge)),
      title: Text('${m.home} vs ${m.away}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      subtitle: Text('${m.league} · ${m.stadium}\n${m.market}  •  Odds ${m.pickOdds}', style: const TextStyle(fontSize: 10)),
      isThreeLine: true,
      trailing: Container(padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: m.pick == 'DRAW' ? const Color(0xFFFFC83D) : Colors.green, borderRadius: BorderRadius.circular(6)),
        child: Text(m.pick, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold))),
    ),
  );

  Widget _resultRow(String home, String score, String away, String outcome) => Card(
    margin: const EdgeInsets.fromLTRB(10, 4, 10, 4), elevation: 0,
    child: ListTile(dense: true, title: Text('$home    $score    $away', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: outcome == 'WIN' ? Colors.green : outcome == 'DRAW' ? const Color(0xFFE0A800) : Colors.red, borderRadius: BorderRadius.circular(5)),
        child: Text(outcome, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)))),
  );
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(children: [
    Container(color: const Color(0xFFD50000), padding: const EdgeInsets.all(24), child: const Column(children: [
      CircleAvatar(radius: 30, backgroundColor: Colors.white, child: Icon(Icons.person, size: 34, color: Color(0xFFD50000))),
      SizedBox(height: 8), Text('Football Fan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      Text('BOOMGRATULATIONS Member', style: TextStyle(color: Colors.white70, fontSize: 11)),
    ])),
    for (final item in const [
      ['My Picks', Icons.stars_outlined], ['Notifications', Icons.notifications_none],
      ['Settings', Icons.settings_outlined], ['Help & Support', Icons.help_outline],
      ['About BOOMGRATULATIONS', Icons.info_outline],
    ]) Card(margin: const EdgeInsets.fromLTRB(12, 5, 12, 5), elevation: 0,
      child: ListTile(dense: true, leading: Icon(item[1] as IconData, color: const Color(0xFFD50000)),
        title: Text(item[0] as String, style: const TextStyle(fontSize: 12)), trailing: const Icon(Icons.chevron_right))),
    const Padding(padding: EdgeInsets.all(16), child: Text('Predictions and odds are informational only. Match data in demo mode is illustrative, not verified live data.', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.black54))),
  ]);
}
