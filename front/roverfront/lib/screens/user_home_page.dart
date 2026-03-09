// user_home_page.dart
// Home screen for role = 'user' (event attendee).
// Data layer wired to EventService — no HTTP calls to the old Flask server.

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import 'event_detail_page.dart';

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
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rover — Events'),
        backgroundColor: const Color(0xFF478DE0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search events…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                // Type filter
                DropdownButton<String>(
                  value: _selectedType ?? '',
                  hint: const Text('Type'),
                  underline: const SizedBox(),
                  items: _eventTypes.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.isEmpty ? 'All types' : t),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedType = val),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.search, color: Color(0xFF478DE0)),
                  onPressed: _search,
                  tooltip: 'Search',
                ),
                if (_isSearching)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.red),
                    onPressed: _clearSearch,
                    tooltip: 'Clear',
                  ),
              ],
            ),
          ),
          // ── Event list ─────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _events.isEmpty
                    ? const Center(child: Text('No events found.'))
                    : RefreshIndicator(
                        onRefresh: _loadEvents,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _events.length,
                          itemBuilder: (context, index) {
                            final event = _events[index];
                            final eventDate = event['event_date'] != null
                                ? DateTime.tryParse(event['event_date'] as String)
                                : null;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF73AEF5),
                                  child: Text(
                                    (event['name'] as String? ?? '?')[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  event['name'] as String? ?? 'Unnamed Event',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (eventDate != null)
                                      Text(
                                        '${eventDate.day}/${eventDate.month}/${eventDate.year}',
                                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                    if (event['event_type'] != null)
                                      Text(
                                        event['event_type'] as String,
                                        style: const TextStyle(color: Color(0xFF478DE0), fontSize: 12),
                                      ),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EventDetailPage(
                                      eventId: event['id'] as int,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
