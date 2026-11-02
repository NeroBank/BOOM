import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiKey = String.fromEnvironment('API_FOOTBALL_KEY');
const String apiBase = 'https://v3.football.api-sports.io';
const Color brandRed = Color(0xFFD50000);
const Color winGreen = Color(0xFF218838);
const Color drawGold = Color(0xFFFFC107);
const Color lostRed = Color(0xFFD50000);
const String appLogo = 'assets/icon/1793295048387.jpg';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

class FootballApi {
  FootballApi._();
  static final FootballApi instance = FootballApi._();

  bool get hasKey => apiKey.trim().isNotEmpty;

  Future<List<Map<String, dynamic>>> getFixtures({
    String? date,
    String? status,
  }) async {
    final query = <String, String>{};
    if (date != null) {
      query['date'] = date;
    } else if (status == 'live') {
      query['live'] = 'all';
    } else {
      final now = DateTime.now();
      query['from'] = _date(now);
      query['to'] = _date(now.add(const Duration(days: 3)));
    }
    if (status != null && status != 'live') query['status'] = status;

    final data = await _request('/fixtures', query);
    return _responseList(data);
  }

  Future<List<Map<String, dynamic>>> getStandings(int leagueId) async {
    final now = DateTime.now();
    final season = now.month >= 7 ? now.year : now.year - 1;
    final data = await _request('/standings', {
      'league': '$leagueId',
      'season': '$season',
    });
    final response = _responseList(data);
    if (response.isEmpty) return [];
    final league = response.first['league'];
    if (league is! Map) return [];
    final standings = league['standings'];
    if (standings is! List || standings.isEmpty) return [];
    final firstGroup = standings.first;
    if (firstGroup is! List) return [];
    return firstGroup.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> _request(
    String endpoint,
    Map<String, String> query,
  ) async {
    if (!hasKey) {
      throw Exception('API key is missing. Add API_FOOTBALL_KEY to GitHub Actions secrets.');
    }
    final uri = Uri.parse('$apiBase$endpoint').replace(queryParameters: query);
    final response = await http.get(
      uri,
      headers: {'x-apisports-key': apiKey},
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('Football data service returned ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response from football data service.');
    }
    final errors = decoded['errors'];
    if (errors is Map && errors.isNotEmpty) {
      throw Exception(errors.values.join(', '));
    }
    return decoded;
  }

  List<Map<String, dynamic>> _responseList(Map<String, dynamic> data) {
    final value = data['response'];
    if (value is! List) return [];
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _loading = false;
  String? _error;
  String _fixtureFilter = 'All';
  List<Map<String, dynamic>> _fixtures = [];
  List<Map<String, dynamic>> _live = [];
  List<Map<String, dynamic>> _standings = [];
  int _leagueId = 39;
  String _leagueName = 'Premier League';

  static const Map<String, int> leagues = {
    'Premier League': 39,
    'La Liga': 140,
    'Serie A': 135,
    'Bundesliga': 78,
    'Ligue 1': 61,
    'Nigeria Premier League': 399,
    'UEFA Champions League': 2,
  };

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        FootballApi.instance.getFixtures(),
        FootballApi.instance.getFixtures(status: 'live'),
        FootballApi.instance.getStandings(_leagueId),
      ]);
      if (!mounted) return;
      setState(() {
        _fixtures = results[0];
        _live = results[1];
        _standings = results[2];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeLeague(String name) async {
    setState(() {
      _leagueName = name;
      _leagueId = leagues[name]!;
      _loading = true;
      _error = null;
    });
    try {
      final table = await FootballApi.instance.getStandings(_leagueId);
      if (mounted) setState(() => _standings = table);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _fixturesPage(),
      _livePage(),
      _picksPage(),
      _tipsPage(),
      _tablePage(),
      _accountPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                appLogo,
                width: 35,
                height: 35,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, size: 32),
              ),
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'BOOMGRATULATIONS',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh data',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) _errorBanner(_error!),
          Expanded(child: pages[_tab]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Fixtures'),
          NavigationDestination(icon: Icon(Icons.circle, size: 17), label: 'Live'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Picks'),
          NavigationDestination(icon: Icon(Icons.lightbulb_outline), label: 'Tips'),
          NavigationDestination(icon: Icon(Icons.leaderboard), label: 'Table'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.orange.withValues(alpha: 0.15),
      child: Text(message, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _fixturesPage() {
    final matches = _fixtures.where((m) {
      final status = _statusShort(m);
      if (_fixtureFilter == 'All') return true;
      if (_fixtureFilter == 'Finished') return const ['FT', 'AET', 'PEN'].contains(status);
      if (_fixtureFilter == 'Upcoming') return status == 'NS';
      return false;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _welcomeBanner(),
          const SizedBox(height: 15),
          _sectionTitle('Football fixtures', 'Real match data'),
          const SizedBox(height: 10),
          _filterChips(),
          const SizedBox(height: 8),
          if (matches.isEmpty)
            _emptyState('No fixtures found', 'Refresh later or check your API plan.')
          else
            ...matches.map(_matchCard),
        ],
      ),
    );
  }

  Widget _welcomeBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [brandRed, Color(0xFF850000)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR FOOTBALL CENTRE', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.2)),
          SizedBox(height: 7),
          Text('Small details.\nSmarter decisions.', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text('Fixtures 鈥� Live scores 鈥� League tables', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _filterChips() {
    return Wrap(
      spacing: 8,
      children: ['All', 'Upcoming', 'Finished'].map((filter) {
        return ChoiceChip(
          label: Text(filter),
          selected: _fixtureFilter == filter,
          selectedColor: brandRed.withValues(alpha: 0.18),
          onSelected: (_) => setState(() => _fixtureFilter = filter),
        );
      }).toList(),
    );
  }

  Widget _livePage() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _sectionTitle('Live matches', 'Scores update when refreshed'),
          const SizedBox(height: 12),
          if (_live.isEmpty)
            _emptyState('No live matches right now', 'Live fixtures will appear here when available.')
          else
            ..._live.map(_matchCard),
        ],
      ),
    );
  }

  Widget _picksPage() {
    final rows = _standings;
    final picks = <Map<String, dynamic>>[];
    for (final fixture in _fixtures) {
      final teams = fixture['teams'];
      if (teams is! Map) continue;
      final home = teams['home'];
      final away = teams['away'];
      if (home is! Map || away is! Map) continue;
      final homeId = home['id'];
      final awayId = away['id'];
      final homeRow = rows.where((r) => r['team'] is Map && r['team']['id'] == homeId).firstOrNull;
      final awayRow = rows.where((r) => r['team'] is Map && r['team']['id'] == awayId).firstOrNull;
      if (homeRow == null || awayRow == null) continue;
      final hp = _number(homeRow['points']);
      final ap = _number(awayRow['points']);
      if ((hp - ap).abs() < 4) continue;
      picks.add({
        'fixture': fixture,
        'selection': hp > ap ? 'Home team has stronger table points' : 'Away team has stronger table points',
        'edge': (hp - ap).abs(),
      });
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _sectionTitle('Table-based picks', 'Simple statistical comparison'),
        const SizedBox(height: 8),
        const Text('These are basic comparisons using the selected league table, not guaranteed results or a trained AI model.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        if (picks.isEmpty)
          _emptyState('Not enough data for picks', 'Load the league table and upcoming fixtures first.')
        else
          ...picks.map((pick) => Card(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fixtureTeams(pick['fixture'] as Map<String, dynamic>),
                  const SizedBox(height: 8),
                  Text(pick['selection'] as String, style: const TextStyle(fontWeight: FontWeight.bold, color: winGreen)),
                  Text('Points difference: ${pick['edge']}', style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          )),
      ],
    );
  }

  Widget _tipsPage() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _sectionTitle('Football tips', 'How to read the numbers'),
        const SizedBox(height: 12),
        _tipCard(Icons.table_chart, 'Check the league table', 'Compare points, position, goals scored and goals conceded.'),
        _tipCard(Icons.home_outlined, 'Separate home and away form', 'A team can be strong at home but weaker when playing away.'),
        _tipCard(Icons.history, 'Review recent form and H2H', 'Look at recent results and head-to-head meetings, while remembering that past results do not guarantee the next result.'),
        _tipCard(Icons.sports_soccer, 'Check team news', 'Injuries, suspensions and rotation can change a match outlook.'),
        _tipCard(Icons.verified_outlined, 'Use verified information', 'Confirm match time, competition and team news before making a decision.'),
      ],
    );
  }

  Widget _tablePage() {
    return RefreshIndicator(
      onRefresh: () async => _changeLeague(_leagueName),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _sectionTitle('League table', 'Choose a competition'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _leagueName,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'League'),
            items: leagues.keys.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
            onChanged: (value) { if (value != null) _changeLeague(value); },
          ),
          const SizedBox(height: 12),
          if (_standings.isEmpty)
            _emptyState('No table data available', 'Check your API key and league access.')
          else
            _standingsTable(),
          const SizedBox(height: 12),
          const Text('Position colours: 1st and 3rd green; 4th鈥�10th yellow; 11th鈥�20th blue; relegation places red when identified by the competition data.', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _standingsTable() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('Team')),
            DataColumn(label: Text('P')),
            DataColumn(label: Text('GD')),
            DataColumn(label: Text('Pts')),
            DataColumn(label: Text('Form')),
          ],
          rows: _standings.map((row) {
            final rank = _number(row['rank']);
            final team = row['team'] is Map ? row['team']['name']?.toString() ?? 'Unknown' : 'Unknown';
            final description = (row['description'] ?? '').toString().toLowerCase();
            final color = _positionColor(rank, description);
            return DataRow(cells: [
              DataCell(_positionBadge(rank, color)),
              DataCell(SizedBox(width: 145, child: Text(team, overflow: TextOverflow.ellipsis))),
              DataCell(Text('${row['all'] is Map ? row['all']['played'] ?? 0 : 0}')),
              DataCell(Text('${row['goalsDiff'] ?? 0}')),
              DataCell(Text('${row['points'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(_formDots((row['form'] ?? '').toString())),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _accountPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(appLogo, width: 90, height: 90, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.sports_soccer, size: 80, color: brandRed)),
              ),
              const SizedBox(height: 12),
              const Text('BOOMGRATULATIONS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const Text('Football information at a glance', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _tipCard(Icons.cloud_done_outlined, 'Data connection', FootballApi.instance.hasKey ? 'API key detected in this build.' : 'API key has not been supplied to this build.'),
        _tipCard(Icons.info_outline, 'About predictions', 'Current picks are basic table comparisons. A genuine AI model and verified prediction service can be added in a later stage.'),
        _tipCard(Icons.refresh, 'Refresh app data', 'Use the refresh icon at the top of the screen to request the latest available data.'),
        const SizedBox(height: 12),
        const Text('BOOMGRATULATIONS 鈥� Version 1.0.0', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _matchCard(Map<String, dynamic> fixture) {
    final fixtureInfo = fixture['fixture'] is Map ? fixture['fixture'] as Map : <String, dynamic>{};
    final status = fixtureInfo['status'] is Map ? fixtureInfo['status'] as Map : <String, dynamic>{};
    final goals = fixture['goals'] is Map ? fixture['goals'] as Map : <String, dynamic>{};
    final league = fixture['league'] is Map ? fixture['league'] as Map : <String, dynamic>{};
    final short = (status['short'] ?? 'NS').toString();
    final time = (status['elapsed'] != null) ? "${status['elapsed']}'" : short;
    final dateText = fixtureInfo['date']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text('${league['name'] ?? 'Football'} 鈥� ${league['country'] ?? ''}', style: const TextStyle(fontSize: 10, color: Colors.grey))),
                _statusBadge(short, time),
              ],
            ),
            const SizedBox(height: 10),
            _fixtureTeams(fixture, goals: goals),
            const SizedBox(height: 7),
            Align(alignment: Alignment.centerRight, child: Text(_formatDate(dateText), style: const TextStyle(fontSize: 10, color: Colors.grey))),
          ],
        ),
      ),
    );
  }

  Widget _fixtureTeams(Map<String, dynamic> fixture, {Map<String, dynamic>? goals}) {
    final teams = fixture['teams'] is Map ? fixture['teams'] as Map : <String, dynamic>{};
    final home = teams['home'] is Map ? teams['home'] as Map : <String, dynamic>{};
    final away = teams['away'] is Map ? teams['away'] as Map : <String, dynamic>{};
    final score = goals ?? (fixture['goals'] is Map ? fixture['goals'] as Map<String, dynamic> : <String, dynamic>{});
    final homeScore = score['home'];
    final awayScore = score['away'];
    return Row(
      children: [
        Expanded(child: _teamName(home['name']?.toString() ?? 'Home team', home['logo']?.toString())),
        SizedBox(
          width: 65,
          child: Text(
            homeScore == null && awayScore == null ? 'VS' : '$homeScore - $awayScore',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ),
        Expanded(child: _teamName(away['name']?.toString() ?? 'Away team', away['logo']?.toString(), alignEnd: true)),
      ],
    );
  }

  Widget _teamName(String name, String? logo, {bool alignEnd = false}) {
    return Row(
      mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!alignEnd) ...[
          _teamLogo(logo),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: alignEnd ? TextAlign.right : TextAlign.left, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        if (alignEnd) ...[
          const SizedBox(width: 6),
          _teamLogo(logo),
        ],
      ],
    );
  }

  Widget _teamLogo(String? url) {
    if (url == null || url.isEmpty) return const SizedBox(width: 23, height: 23);
    return Image.network(url, width: 23, height: 23, fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox(width: 23, height: 23));
  }

  Widget _statusBadge(String status, String label) {
    final live = const ['1H', '2H', 'HT', 'ET', 'P', 'LIVE'].contains(status);
    final finished = const ['FT', 'AET', 'PEN'].contains(status);
    final color = live ? winGreen : finished ? Colors.grey : brandRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _emptyState(String title, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 45, horizontal: 18),
      child: Column(
        children: [
          const Icon(Icons.sports_soccer_outlined, size: 42, color: Colors.grey),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _tipCard(IconData icon, String title, String body) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: brandRed.withValues(alpha: 0.10), child: Icon(icon, color: brandRed)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(body, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _positionBadge(int rank, Color color) {
    return Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
      child: Text('$rank', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Color _positionColor(int rank, String description) {
    if (description.contains('relegation')) return lostRed;
    if (rank == 1 || rank == 3) return winGreen;
    if (rank >= 4 && rank <= 10) return const Color(0xFFE0A800);
    if (rank >= 11 && rank <= 20) return const Color(0xFF1976D2);
    return Colors.grey;
  }

  Widget _formDots(String form) {
    final chars = form.split('').take(5).toList();
    if (chars.isEmpty) return const Text('-');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: chars.map((value) {
        final color = value == 'W' ? winGreen : value == 'D' ? drawGold : lostRed;
        return Container(
          width: 15,
          height: 15,
          margin: const EdgeInsets.only(right: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(value, style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
        );
      }).toList(),
    );
  }

  String _statusShort(Map<String, dynamic> fixture) {
    final info = fixture['fixture'];
    if (info is Map && info['status'] is Map) {
      return (info['status']['short'] ?? 'NS').toString();
    }
    return 'NS';
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year}  $hour:$minute';
  }

  int _number(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
