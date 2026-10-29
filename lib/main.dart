import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiKey = String.fromEnvironment('API_FOOTBALL_KEY');
const String apiBase = 'https://v3.football.api-sports.io';

void main() {
  runApp(const BoomgratulationsApp());
}

class BoomgratulationsApp extends StatefulWidget {
  const BoomgratulationsApp({super.key});

  @override
  State<BoomgratulationsApp> createState() => _BoomgratulationsAppState();
}

class _BoomgratulationsAppState extends State<BoomgratulationsApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BOOMGRATULATIONS',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: HomeScreen(
        themeMode: _themeMode,
        onThemeChanged: _setThemeMode,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFD50000),
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F6F8),
      cardColor: isDark ? const Color(0xFF202020) : Colors.white,
      dividerColor: isDark ? Colors.white12 : Colors.black12,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF9F0000) : const Color(0xFFD50000),
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1B1B1B) : Colors.white,
        indicatorColor:
            isDark ? const Color(0xFF512020) : const Color(0xFFFFDADA),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (states) => TextStyle(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF303030) : const Color(0xFFF0F0F0),
        side: BorderSide.none,
      ),
    );
  }
}

enum MatchOutcome { win, draw, lost, upcoming }

class MatchItem {
  const MatchItem({
    required this.home,
    required this.away,
    required this.league,
    required this.time,
    this.homePosition = '-',
    this.awayPosition = '-',
    this.homeForm = 'W D W',
    this.awayForm = 'L D W',
    this.homeGoals = '-',
    this.awayGoals = '-',
    this.outcome = MatchOutcome.upcoming,
    this.prediction = 'Home or Draw',
    this.confidence = 68,
    this.status = 'Upcoming',
  });

  final String home;
  final String away;
  final String league;
  final String time;
  final String homePosition;
  final String awayPosition;
  final String homeForm;
  final String awayForm;
  final String homeGoals;
  final String awayGoals;
  final MatchOutcome outcome;
  final String prediction;
  final int confidence;
  final String status;

  factory MatchItem.fromApi(Map<String, dynamic> json) {
    final fixture = json['fixture'] as Map<String, dynamic>? ?? {};
    final teams = json['teams'] as Map<String, dynamic>? ?? {};
    final leagueData = json['league'] as Map<String, dynamic>? ?? {};
    final goals = json['goals'] as Map<String, dynamic>? ?? {};
    final home = teams['home'] as Map<String, dynamic>? ?? {};
    final away = teams['away'] as Map<String, dynamic>? ?? {};
    final statusData = fixture['status'] as Map<String, dynamic>? ?? {};
    final dateText = fixture['date']?.toString() ?? '';
    String timeText = 'TBD';
    if (dateText.isNotEmpty) {
      final parsed = DateTime.tryParse(dateText)?.toLocal();
      if (parsed != null) {
        final hour = parsed.hour.toString().padLeft(2, '0');
        final minute = parsed.minute.toString().padLeft(2, '0');
        timeText = '$hour:$minute';
      }
    }

    final homeGoal = goals['home'];
    final awayGoal = goals['away'];
    final isFinished = const ['FT', 'AET', 'PEN']
        .contains(statusData['short']?.toString());
    MatchOutcome outcome = MatchOutcome.upcoming;
    if (isFinished && homeGoal is num && awayGoal is num) {
      if (homeGoal > awayGoal) {
        outcome = MatchOutcome.win;
      } else if (homeGoal == awayGoal) {
        outcome = MatchOutcome.draw;
      } else {
        outcome = MatchOutcome.lost;
      }
    }

    return MatchItem(
      home: home['name']?.toString() ?? 'Home team',
      away: away['name']?.toString() ?? 'Away team',
      league: leagueData['name']?.toString() ?? 'Football',
      time: timeText,
      homeGoals: homeGoal?.toString() ?? '-',
      awayGoals: awayGoal?.toString() ?? '-',
      outcome: outcome,
      status: statusData['long']?.toString() ?? 'Upcoming',
    );
  }
}

const List<MatchItem> demoMatches = [
  MatchItem(
    home: 'Arsenal',
    away: 'Chelsea',
    league: 'Premier League',
    time: '17:30',
    homePosition: '2',
    awayPosition: '6',
    homeForm: 'W W D W W',
    awayForm: 'W L W D W',
    prediction: 'Arsenal or Draw',
    confidence: 78,
  ),
  MatchItem(
    home: 'Liverpool',
    away: 'Tottenham',
    league: 'Premier League',
    time: '20:00',
    homePosition: '1',
    awayPosition: '5',
    homeForm: 'W W W D W',
    awayForm: 'L W D L W',
    prediction: 'Over 1.5 Goals',
    confidence: 82,
  ),
  MatchItem(
    home: 'Barcelona',
    away: 'Sevilla',
    league: 'La Liga',
    time: '18:00',
    homePosition: '3',
    awayPosition: '12',
    homeForm: 'W W W L W',
    awayForm: 'D L W L D',
    prediction: 'Barcelona Win',
    confidence: 75,
  ),
  MatchItem(
    home: 'Inter',
    away: 'Roma',
    league: 'Serie A',
    time: '19:45',
    homePosition: '1',
    awayPosition: '8',
    homeForm: 'W D W W W',
    awayForm: 'W D L W D',
    prediction: 'Over 1.5 Goals',
    confidence: 71,
  ),
];

class FootballApi {
  Future<List<MatchItem>> fetchFixtures() async {
    if (apiKey.trim().isEmpty) {
      throw Exception(
        'API key is missing. Add API_FOOTBALL_KEY to your GitHub Actions build secret.',
      );
    }

    final today = DateTime.now();
    final from = _dateString(today);
    final to = _dateString(today.add(const Duration(days: 3)));
    final uri = Uri.parse('$apiBase/fixtures').replace(
      queryParameters: {
        'from': from,
        'to': to,
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'x-apisports-key': apiKey,
      },
    ).timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw Exception('Football API returned status ${response.statusCode}.');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final errors = decoded['errors'];
    if (errors is Map && errors.isNotEmpty) {
      throw Exception('Football API error: ${errors.values.join(', ')}');
    }

    final responseItems = decoded['response'];
    if (responseItems is! List) {
      throw Exception('The API returned an unexpected fixture format.');
    }

    return responseItems
        .whereType<Map<String, dynamic>>()
        .map(MatchItem.fromApi)
        .toList();
  }

  String _dateString(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FootballApi _footballApi = FootballApi();
  int _tab = 0;
  bool _loading = false;
  String? _error;
  List<MatchItem> _matches = demoMatches;

  @override
  void initState() {
    super.initState();
    _refresh(showMessage: false);
  }

  Future<void> _refresh({bool showMessage = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _footballApi.fetchFixtures();
      if (!mounted) return;
      setState(() {
        _matches = result;
        _loading = false;
      });
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fixtures updated successfully.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _fixturesPage(),
      _predictionsPage(),
      _tipsPage(),
      _tablePage(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            Icon(Icons.sports_soccer, size: 25),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'BOOMGRATULATIONS',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<ThemeMode>(
            tooltip: 'Change appearance',
            icon: const Icon(Icons.brightness_6),
            initialValue: widget.themeMode,
            onSelected: widget.onThemeChanged,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ThemeMode.light,
                child: _themeMenuItem(Icons.light_mode, 'Light Mode'),
              ),
              PopupMenuItem(
                value: ThemeMode.dark,
                child: _themeMenuItem(Icons.dark_mode, 'Dark Mode'),
              ),
              PopupMenuItem(
                value: ThemeMode.system,
                child: _themeMenuItem(Icons.settings_brightness, 'System Default'),
              ),
            ],
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh fixtures',
          ),
        ],
      ),
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Fixtures',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI Picks',
          ),
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outline),
            selectedIcon: Icon(Icons.lightbulb),
            label: 'Tips',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard),
            label: 'Table',
          ),
        ],
      ),
    );
  }

  Widget _themeMenuItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }

  Widget _fixturesPage() {
    return RefreshIndicator(
      onRefresh: () => _refresh(showMessage: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _welcomeBanner(),
          const SizedBox(height: 14),
          _sectionTitle('Today鈥檚 Fixtures', 'Matches and kickoff times'),
          if (_loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            _messageCard(
              icon: Icons.info_outline,
              title: 'Showing demo fixtures',
              message:
                  'Live fixtures could not be loaded. ${_error!} You can still explore the app using sample data.',
            ),
          ],
          const SizedBox(height: 8),
          if (_matches.isEmpty)
            _messageCard(
              icon: Icons.event_busy,
              title: 'No fixtures found',
              message: 'Try refreshing, or check again later.',
            )
          else
            ..._matches.map(_matchCard),
          const SizedBox(height: 12),
          _sectionTitle('Quick Form Guide', 'Recent results at a glance'),
          _formLegend(),
        ],
      ),
    );
  }

  Widget _predictionsPage() {
    final matches = _matches;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _sectionTitle('AI Predictions', 'Demo suggestions 鈥� not guaranteed results'),
        _messageCard(
          icon: Icons.auto_awesome,
          title: 'Prediction guide',
          message:
              'These sample picks are illustrative. The app does not yet calculate a verified AI model from live team statistics.',
        ),
        const SizedBox(height: 8),
        ...matches.map((match) => _predictionCard(match)),
      ],
    );
  }

  Widget _tipsPage() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _sectionTitle('Football Tips', 'Quick information for match analysis'),
        _tipCard(
          Icons.sports_soccer,
          'Over 1.5 Goals',
          'Consider recent scoring and conceding records for both teams.',
          const Color(0xFF18864B),
        ),
        _tipCard(
          Icons.balance,
          'Double Chance',
          'Compare home and away form before considering 1X or X2.',
          const Color(0xFFB8860B),
        ),
        _tipCard(
          Icons.shield_outlined,
          'Team Form',
          'Check the last five matches, opponent strength, and home/away splits.',
          const Color(0xFF2879C7),
        ),
        _tipCard(
          Icons.table_chart_outlined,
          'League Position',
          'Use the table as context, not as the only reason for a prediction.',
          const Color(0xFFD50000),
        ),
        _messageCard(
          icon: Icons.info_outline,
          title: 'Please remember',
          message:
              'Tips are informational and can be wrong. No prediction guarantees a win.',
        ),
      ],
    );
  }

  Widget _tablePage() {
    final rows = <_LeagueRow>[
      _LeagueRow(1, 'Liverpool', 24, 58),
      _LeagueRow(2, 'Arsenal', 23, 52),
      _LeagueRow(3, 'Barcelona', 22, 49),
      _LeagueRow(4, 'Manchester City', 22, 47),
      _LeagueRow(5, 'Tottenham', 21, 42),
      _LeagueRow(6, 'Chelsea', 20, 38),
      _LeagueRow(7, 'Aston Villa', 20, 36),
      _LeagueRow(8, 'Newcastle', 19, 34),
      _LeagueRow(9, 'West Ham', 18, 31),
      _LeagueRow(10, 'Brighton', 18, 29),
      _LeagueRow(11, 'Fulham', 17, 27),
      _LeagueRow(12, 'Wolves', 17, 25),
      _LeagueRow(13, 'Crystal Palace', 16, 23),
      _LeagueRow(14, 'Everton', 16, 22),
      _LeagueRow(15, 'Brentford', 15, 21),
      _LeagueRow(16, 'Nottingham Forest', 15, 19),
      _LeagueRow(17, 'Luton Town', 14, 17),
      _LeagueRow(18, 'Burnley', 14, 13),
      _LeagueRow(19, 'Sheffield United', 13, 10),
      _LeagueRow(20, 'Bournemouth', 13, 8),
    ];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _sectionTitle('League Table', 'Illustrative sample standings'),
        _messageCard(
          icon: Icons.info_outline,
          title: 'Sample data',
          message:
              'This table is for layout demonstration and is not a live league table. Team positions and points must be connected to a standings API for real rankings.',
        ),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: const Row(
                  children: [
                    SizedBox(width: 34, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                    Expanded(child: Text('Team', style: TextStyle(fontWeight: FontWeight.bold))),
                    SizedBox(width: 40, child: Text('MP', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                    SizedBox(width: 45, child: Text('Pts', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              ...rows.map((row) {
                final color = _tablePositionColor(row.position);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 25,
                        height: 25,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${row.position}',
                          style: TextStyle(
                            color: row.position >= 4 && row.position <= 10
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: Text(row.team, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 40, child: Text('${row.played}', textAlign: TextAlign.center)),
                      SizedBox(width: 45, child: Text('${row.points}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _tableLegend(),
      ],
    );
  }

  Color _tablePositionColor(int position) {
    if (position == 1 || position == 3) return const Color(0xFF218838);
    if (position >= 4 && position <= 10) return const Color(0xFFFFD54F);
    if (position >= 11 && position <= 17) return const Color(0xFF2879C7);
    return const Color(0xFFD50000);
  }

  Widget _welcomeBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD50000), Color(0xFF8E0000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR MATCH CENTRE',
            style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 7),
          Text(
            'Predict smarter.',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 5),
          Text(
            'Fixtures, form guides and match insights in one place.',
            style: TextStyle(color: Colors.white, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _matchCard(MatchItem match) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.league,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _outcomeBadge(match),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _teamLine(match.home, match.homePosition, match.homeForm)),
                SizedBox(
                  width: 58,
                  child: Column(
                    children: [
                      Text(
                        match.homeGoals == '-' || match.awayGoals == '-'
                            ? match.time
                            : '${match.homeGoals} - ${match.awayGoals}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(match.status, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Expanded(child: _teamLine(match.away, match.awayPosition, match.awayForm, alignEnd: true)),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            const SizedBox(height: 9),
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFD50000)),
                const SizedBox(width: 6),
                Expanded(child: Text('Tip: ${match.prediction}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                Text('${match.confidence}%', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamLine(String team, String position, String form, {bool alignEnd = false}) {
    final alignment = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!alignEnd) ...[
              _positionChip(position),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                team,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
            if (alignEnd) ...[
              const SizedBox(width: 5),
              _positionChip(position),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Text(form, textAlign: alignEnd ? TextAlign.end : TextAlign.start, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _positionChip(String position) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(position == '-' ? '鈥�' : '#$position', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _outcomeBadge(MatchItem match) {
    final Color color;
    final String text;
    switch (match.outcome) {
      case MatchOutcome.win:
        color = const Color(0xFF218838);
        text = 'WIN';
        break;
      case MatchOutcome.draw:
        color = const Color(0xFFFFC107);
        text = 'DRAW';
        break;
      case MatchOutcome.lost:
        color = const Color(0xFFD50000);
        text = 'LOST';
        break;
      case MatchOutcome.upcoming:
        color = const Color(0xFF2879C7);
        text = 'FIXTURE';
        break;
    }

    final foreground = match.outcome == MatchOutcome.draw ? Colors.black : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: foreground, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }

  Widget _predictionCard(MatchItem match) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(match.league, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 7),
            Text('${match.home} vs ${match.away}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFFD50000)),
                const SizedBox(width: 7),
                Expanded(child: Text(match.prediction, style: const TextStyle(fontWeight: FontWeight.bold))),
                Text('${match.confidence}%', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF218838))),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: match.confidence.clamp(0, 100) / 100,
                minHeight: 6,
                backgroundColor: Theme.of(context).dividerColor,
                color: const Color(0xFFD50000),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipCard(IconData icon, String title, String description, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(description),
        ),
      ),
    );
  }

  Widget _messageCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFD50000)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formLegend() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: const [
            _FormDot(label: 'Win', color: Color(0xFF218838)),
            _FormDot(label: 'Draw', color: Color(0xFFFFC107)),
            _FormDot(label: 'Lost', color: Color(0xFFD50000)),
          ],
        ),
      ),
    );
  }

  Widget _tableLegend() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: const [
            _FormDot(label: '1st & 3rd: Green', color: Color(0xFF218838)),
            _FormDot(label: '4th鈥�10th: Yellow', color: Color(0xFFFFD54F)),
            _FormDot(label: '11th鈥�17th: Blue', color: Color(0xFF2879C7)),
            _FormDot(label: '18th鈥�20th: Red', color: Color(0xFFD50000)),
          ],
        ),
      ),
    );
  }
}

class _FormDot extends StatelessWidget {
  const _FormDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _LeagueRow {
  const _LeagueRow(this.position, this.team, this.played, this.points);

  final int position;
  final String team;
  final int played;
  final int points;
}
