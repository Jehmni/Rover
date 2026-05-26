// user_home_page.dart
// Home screen for role = 'user' (event attendee).
// Data layer wired to EventService.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../theme/rover_theme.dart';
import 'event_detail_page.dart';
import 'user_guide_page.dart';

class UserHomePage extends StatefulWidget {
  const UserHomePage({super.key});

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String? _selectedType;
  bool _isSearching = false;

  static const _eventTypes = ['', 'Conference', 'Concert', 'Sports', 'Workshop', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final events = await EventService.getEvents();
      setState(() => _events = events);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _search() async {
    setState(() { _isSearching = true; _isLoading = true; });
    try {
      final results = await EventService.searchEvents(
        name: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        eventType: (_selectedType == null || _selectedType!.isEmpty) ? null : _selectedType,
      );
      setState(() => _events = results);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearSearch() async {
    _searchController.clear();
    setState(() { _isSearching = false; _selectedType = null; });
    await _loadEvents();
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: RoverColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RoverColors.surface,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: RoverColors.primary,
            foregroundColor: Colors.white,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 0, 16),
              title: Text(
                'Events',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              background: Container(color: RoverColors.primary),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: 'Help',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UserGuidePage(role: 'user'),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign Out',
                onPressed: _logout,
              ),
            ],
          ),

          // ── Search bar ───────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.inter(
                          fontSize: 14, color: RoverColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search events…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _isSearching
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _clearSearch,
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Type filter chip
                  PopupMenuButton<String>(
                    tooltip: 'Filter by type',
                    icon: Icon(
                      Icons.tune,
                      color: (_selectedType != null && _selectedType!.isNotEmpty)
                          ? RoverColors.secondary
                          : RoverColors.textSecondary,
                    ),
                    onSelected: (val) {
                      setState(() => _selectedType = val.isEmpty ? null : val);
                      _search();
                    },
                    itemBuilder: (_) => _eventTypes
                        .map((t) => PopupMenuItem(
                              value: t,
                              child: Text(t.isEmpty ? 'All types' : t),
                            ))
                        .toList(),
                  ),
                  IconButton(
                    icon: Icon(Icons.search, color: RoverColors.primary),
                    onPressed: _search,
                    tooltip: 'Search',
                  ),
                ],
              ),
            ),
          ),

          // Active filter chip
          if (_selectedType != null && _selectedType!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  children: [
                    Chip(
                      label: Text(_selectedType!,
                          style: GoogleFonts.inter(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: _clearSearch,
                      backgroundColor: RoverColors.secondaryContainer,
                      labelStyle:
                          TextStyle(color: RoverColors.secondary),
                    ),
                  ],
                ),
              ),
            ),

          // ── Event list ───────────────────────────────────
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_events.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy,
                        size: 56, color: RoverColors.textSecondary),
                    const SizedBox(height: 12),
                    Text('No events found.',
                        style: GoogleFonts.inter(
                            color: RoverColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final event = _events[index];
                    final eventDate = event['event_date'] != null
                        ? DateTime.tryParse(event['event_date'] as String)
                        : null;
                    final name =
                        event['name'] as String? ?? 'Unnamed Event';
                    final type = event['event_type'] as String?;

                    return _EventCard(
                      name: name,
                      eventDate: eventDate,
                      eventType: type,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EventDetailPage(
                            eventId: event['id'] as int,
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _events.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Event card — tonal surface, no explicit border
// ─────────────────────────────────────────────────────────────────────────────
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.name,
    required this.eventDate,
    required this.eventType,
    required this.onTap,
  });

  final String name;
  final DateTime? eventDate;
  final String? eventType;
  final VoidCallback onTap;

  String get _dateLabel {
    if (eventDate == null) return '';
    return '${eventDate!.day}/${eventDate!.month}/${eventDate!.year}  '
        '${eventDate!.hour.toString().padLeft(2, '0')}:'
        '${eventDate!.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: RoverColors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      name[0].toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: RoverColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: RoverColors.textPrimary,
                        ),
                      ),
                      if (eventDate != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 12,
                                color: RoverColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              _dateLabel,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: RoverColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (eventType != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: RoverColors.secondaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            eventType!,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: RoverColors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: RoverColors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
