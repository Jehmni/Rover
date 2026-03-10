// admin_home_page.dart
//
// Organisation admin home screen — 3 tabs:
//   Events  — create, edit, cancel, assign driver, view attendees
//   Members — all drivers and users in this org
//   Invites — generate and manage join codes

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/org_service.dart';
import '../widgets/auth_dialog.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _orgName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrgName();
  }

  Future<void> _loadOrgName() async {
    final org = await OrgService.getMyOrg();
    if (mounted && org != null) {
      setState(() => _orgName = org['name'] as String?);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rover — Admin',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (_orgName != null)
              Text(_orgName!,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF478DE0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.event), text: 'Events'),
            Tab(icon: Icon(Icons.people), text: 'Members'),
            Tab(icon: Icon(Icons.share), text: 'Share'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _EventsTab(),
          _MembersTab(),
          _ShareTab(),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// TAB 1 — EVENTS
// ═════════════════════════════════════════════════════════════

class _EventsTab extends StatefulWidget {
  const _EventsTab();

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  List<Map<String, dynamic>> _events  = [];
  List<Map<String, dynamic>> _drivers = [];
  bool _isLoading = true;
  bool _isActing  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        EventService.getEvents(),
        EventService.getDrivers(),
      ]);
      setState(() {
        _events  = List<Map<String, dynamic>>.from(results[0] as List);
        _drivers = List<Map<String, dynamic>>.from(results[1] as List);
      });
    } catch (e) {
      _err(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Create / Edit event dialog ─────────────────────────────
  void _showEventDialog({Map<String, dynamic>? existing}) {
    final ev = existing; // local non-nullable alias used inside closures
    final nameCtrl = TextEditingController(text: ev?['name'] as String? ?? '');
    final descCtrl = TextEditingController(text: ev?['description'] as String? ?? '');
    final typeCtrl = TextEditingController(text: ev?['event_type'] as String? ?? '');
    final locCtrl  = TextEditingController(text: ev?['location_name'] as String? ?? '');
    DateTime? pickedDate = ev?['event_date'] != null
        ? DateTime.tryParse(ev!['event_date'] as String)
        : null;
    final isEdit = ev != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          title: Text(isEdit ? 'Edit Event' : 'Create Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Event Name *'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Type  (e.g. Conference, Sports)'),
                ),
                TextField(
                  controller: locCtrl,
                  decoration: const InputDecoration(labelText: 'Location Name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pickedDate == null
                            ? 'No date/time selected'
                            : '${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}  '
                              '${pickedDate!.hour.toString().padLeft(2, '0')}:'
                              '${pickedDate!.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: pickedDate == null ? Colors.red[700] : null,
                        ),
                      ),
                    ),
                    TextButton(
                      child: const Text('Pick Date & Time'),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: pickedDate ??
                              DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                        );
                        if (d == null) return;
                        if (!ctx.mounted) return;
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: pickedDate != null
                              ? TimeOfDay(
                                  hour: pickedDate!.hour,
                                  minute: pickedDate!.minute)
                              : const TimeOfDay(hour: 9, minute: 0),
                        );
                        if (t != null) {
                          setDS(() => pickedDate = DateTime(
                              d.year, d.month, d.day, t.hour, t.minute));
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              child: Text(isEdit ? 'Save' : 'Create'),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || pickedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Name and date/time are required.'),
                    backgroundColor: Colors.red,
                  ));
                  return;
                }
                Navigator.of(ctx).pop();
                setState(() => _isActing = true);
                try {
                  if (isEdit) {
                    await EventService.updateEvent(
                      ev['id'] as int,
                      name:         nameCtrl.text.trim(),
                      description:  descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                      eventType:    typeCtrl.text.trim().isEmpty ? null : typeCtrl.text.trim(),
                      locationName: locCtrl.text.trim().isEmpty ? null : locCtrl.text.trim(),
                      eventDate:    pickedDate!,
                    );
                    _snack('Event updated.', Colors.green);
                  } else {
                    await EventService.createEvent(
                      name:         nameCtrl.text.trim(),
                      description:  descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                      eventDate:    pickedDate!,
                      eventType:    typeCtrl.text.trim().isEmpty ? null : typeCtrl.text.trim(),
                      locationName: locCtrl.text.trim().isEmpty ? null : locCtrl.text.trim(),
                    );
                    _snack('Event created!', Colors.green);
                  }
                  await _load();
                } catch (e) {
                  _err(e.toString().replaceFirst('Exception: ', ''));
                } finally {
                  if (mounted) setState(() => _isActing = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Assign driver dialog ───────────────────────────────────
  void _showAssignDriverDialog(int eventId, String eventName) {
    if (_drivers.isEmpty) {
      _err('No drivers registered in this organisation yet.\n'
          'Go to the Invites tab and generate a Driver invite code.');
      return;
    }
    String? selectedId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          title: Text('Assign Driver\n$eventName',
              style: const TextStyle(fontSize: 15)),
          content: DropdownButton<String>(
            value: selectedId,
            hint: const Text('Select a driver'),
            isExpanded: true,
            items: _drivers.map((d) => DropdownMenuItem(
              value: d['id'] as String,
              child: Text(d['full_name'] as String? ?? 'Driver'),
            )).toList(),
            onChanged: (v) => setDS(() => selectedId = v),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              onPressed: selectedId == null
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      setState(() => _isActing = true);
                      try {
                        await EventService.assignDriver(eventId, selectedId!);
                        _snack('Driver assigned!', Colors.green);
                        await _load();
                      } catch (e) {
                        _err(e.toString().replaceFirst('Exception: ', ''));
                      } finally {
                        if (mounted) setState(() => _isActing = false);
                      }
                    },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  // ── View attendees dialog ──────────────────────────────────
  void _showAttendeesDialog(int eventId, String eventName) async {
    showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    try {
      final attendees = await EventService.getEventAttendees(eventId);
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Attendees — $eventName'),
          content: SizedBox(
            width: double.maxFinite,
            child: attendees.isEmpty
                ? const Text('No attendees have subscribed yet.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: attendees.length,
                    itemBuilder: (_, i) {
                      final profile =
                          attendees[i]['profiles'] as Map? ?? {};
                      final name = profile['full_name'] as String? ?? 'User';
                      final phone = profile['phone'] as String?;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF73AEF5),
                          child: Text(name[0].toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ),
                        title: Text(name),
                        subtitle: phone != null ? Text(phone) : null,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              child: const Text('Close'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _err(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  // ── Cancel event ───────────────────────────────────────────
  Future<void> _cancelEvent(int eventId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Event?'),
        content: Text('This will cancel "$name". Attendees will no longer see it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isActing = true);
    try {
      await EventService.cancelEvent(eventId);
      _snack('Event cancelled.', Colors.orange);
      await _load();
    } catch (e) {
      _err(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  void _err(String msg) {
    if (!mounted) return;
    showErrorDialog(context, msg);
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isActing ? null : () => _showEventDialog(),
        backgroundColor: const Color(0xFF478DE0),
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? const Center(
                  child: Text('No events yet. Tap + to create one.',
                      style: TextStyle(color: Colors.grey, fontSize: 16)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    itemCount: _events.length,
                    itemBuilder: (_, i) {
                      final ev = _events[i];
                      final date = ev['event_date'] != null
                          ? DateTime.tryParse(ev['event_date'] as String)
                          : null;
                      final driverName =
                          (ev['driver'] as Map?)?['full_name'] as String?;
                      final isCancelled =
                          (ev['status'] as String?) == 'cancelled';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: isCancelled ? Colors.grey[100] : null,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ev['name'] as String? ?? 'Unnamed',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isCancelled
                                              ? Colors.grey
                                              : null,
                                        ),
                                      ),
                                    ),
                                    if (isCancelled)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[300],
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Text('CANCELLED',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey)),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (date != null)
                                      Text(
                                        '${date.day}/${date.month}/${date.year}  '
                                        '${date.hour.toString().padLeft(2, '0')}:'
                                        '${date.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                            color: Colors.grey),
                                      ),
                                    if (ev['event_type'] != null)
                                      Text(ev['event_type'] as String,
                                          style: const TextStyle(
                                              color: Color(0xFF478DE0))),
                                    if (ev['location_name'] != null)
                                      Text(ev['location_name'] as String,
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12)),
                                    if (!isCancelled)
                                      Text(
                                        driverName != null
                                            ? 'Driver: $driverName'
                                            : 'No driver assigned',
                                        style: TextStyle(
                                          color: driverName != null
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (!isCancelled)
                                OverflowBar(
                                  alignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.people_outline,
                                          size: 18),
                                      label: const Text('Attendees'),
                                      onPressed: _isActing
                                          ? null
                                          : () => _showAttendeesDialog(
                                                ev['id'] as int,
                                                ev['name'] as String? ??
                                                    'Event',
                                              ),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.directions_bus,
                                          size: 18),
                                      label: const Text('Assign Driver'),
                                      onPressed: _isActing
                                          ? null
                                          : () => _showAssignDriverDialog(
                                                ev['id'] as int,
                                                ev['name'] as String? ??
                                                    'Event',
                                              ),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Text('Edit'),
                                      onPressed: _isActing
                                          ? null
                                          : () => _showEventDialog(existing: ev),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.cancel,
                                          size: 18, color: Colors.red),
                                      label: const Text('Cancel',
                                          style:
                                              TextStyle(color: Colors.red)),
                                      onPressed: _isActing
                                          ? null
                                          : () => _cancelEvent(
                                                ev['id'] as int,
                                                ev['name'] as String? ??
                                                    'Event',
                                              ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// TAB 2 — MEMBERS
// ═════════════════════════════════════════════════════════════

class _MembersTab extends StatefulWidget {
  const _MembersTab();

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final members = await OrgService.getOrgMembers();
      if (mounted) setState(() => _members = members);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_members.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No members yet.\nShare the invite link from the Share tab.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 15, height: 1.6),
          ),
        ),
      );
    }

    final admins  = _members.where((m) => m['role'] == 'admin').toList();
    final drivers = _members.where((m) => m['role'] == 'driver').toList();
    final users   = _members.where((m) => m['role'] == 'user').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (admins.isNotEmpty) ...[
            _sectionHeader('Administrators', Icons.manage_accounts,
                Colors.purple),
            ...admins.map((m) => _memberTile(m)),
          ],
          if (drivers.isNotEmpty) ...[
            _sectionHeader('Drivers', Icons.directions_bus, Colors.blue),
            ...drivers.map((m) => _memberTile(m)),
          ],
          if (users.isNotEmpty) ...[
            _sectionHeader('Attendees', Icons.people, const Color(0xFF478DE0)),
            ...users.map((m) => _memberTile(m)),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> m) {
    final name  = m['full_name'] as String? ?? 'Unknown';
    final phone = m['phone']     as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF73AEF5),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(name),
        subtitle: phone != null ? Text(phone) : null,
        trailing: phone != null
            ? IconButton(
                icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                tooltip: 'Copy phone',
                onPressed: () => Clipboard.setData(ClipboardData(text: phone)),
              )
            : null,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// TAB 3 — SHARE  (QR code + invite link)
// ═════════════════════════════════════════════════════════════

class _ShareTab extends StatefulWidget {
  const _ShareTab();

  @override
  State<_ShareTab> createState() => _ShareTabState();
}

class _ShareTabState extends State<_ShareTab> {
  Map<String, dynamic>? _org;
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoading   = true;
  bool _isResetting = false;

  static const _baseUrl = 'https://rover.app/join/';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        OrgService.getMyOrg(),
        OrgService.getPendingRequests(),
      ]);
      if (mounted) {
        setState(() {
          _org             = results[0] as Map<String, dynamic>?;
          _pendingRequests = results[1] as List<Map<String, dynamic>>;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _inviteUrl =>
      '$_baseUrl${_org?['org_token'] ?? ''}';

  Future<void> _shareLink() async {
    await Share.share(
      'Join ${_org?['name'] ?? 'our organisation'} on Rover:\n$_inviteUrl',
    );
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _inviteUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied to clipboard.')),
    );
  }

  Future<void> _resetLink() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Invite Link?'),
        content: const Text(
          'All existing QR codes and shared links will stop working '
          'immediately. A new link will be generated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset Link',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isResetting = true);
    try {
      await OrgService.resetOrgToken(_org!['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        showErrorDialog(
            context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  Future<void> _approveRequest(int requestId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Request?'),
        content: Text('$name will be added to your organisation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await OrgService.approveRequest(requestId);
      await _load();
    } catch (e) {
      if (mounted) {
        showErrorDialog(
            context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _rejectRequest(int requestId, String name) async {
    try {
      await OrgService.rejectRequest(requestId);
      await _load();
    } catch (e) {
      if (mounted) {
        showErrorDialog(
            context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_org == null) {
      return const Center(
        child: Text('Could not load organisation.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final orgToken = _org!['org_token'] as String? ?? '';

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Heading ────────────────────────────────────────
            const Text(
              'Share with your team',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Anyone with this link can join ${_org!['name']} on Rover.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),

            const SizedBox(height: 24),

            // ── QR Code ────────────────────────────────────────
            if (orgToken.isNotEmpty)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: _inviteUrl,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // ── Link display ───────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _inviteUrl,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4A5568),
                        fontFamily: 'monospace',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy,
                        size: 18, color: Color(0xFF478DE0)),
                    tooltip: 'Copy link',
                    onPressed: _copyLink,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Action buttons ─────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _shareLink,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF478DE0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.share),
                label: const Text('Share Invite Link',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 12),

            // ── Reset link ─────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isResetting ? null : _resetLink,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isResetting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.red),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Reset Link (invalidates current QR)',
                    style: TextStyle(fontSize: 13)),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),

            // ── Pending join requests (search fallback only) ───
            // Section only visible when requests exist so admins
            // using QR/link never see an empty placeholder.
            if (_pendingRequests.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.pending_actions,
                      size: 16, color: Color(0xFF478DE0)),
                  const SizedBox(width: 6),
                  Text(
                    'Pending Requests (${_pendingRequests.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...(_pendingRequests.map((req) {
                final reqId  = req['id'] as int;
                final profile =
                    (req['profiles'] as Map?)?.cast<String, dynamic>() ?? {};
                final name  = profile['full_name'] as String? ?? 'Unknown';
                final phone = profile['phone']     as String?;
                final date  = req['created_at'] != null
                    ? DateTime.tryParse(req['created_at'] as String)
                    : null;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFF73AEF5),
                          radius: 20,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              if (phone != null)
                                Text(phone,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              if (date != null)
                                Text(
                                  'Requested ${date.day}/${date.month}/${date.year}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.green),
                          onPressed: () => _approveRequest(reqId, name),
                          child: const Text('Approve'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red),
                          onPressed: () => _rejectRequest(reqId, name),
                          child: const Text('Reject'),
                        ),
                      ],
                    ),
                  ),
                );
              })),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
            ],

            // ── How it works info ──────────────────────────────
            const _HowItWorksCard(),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF7FAFC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'How it works',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
            ),
            SizedBox(height: 10),
            _Step(
              icon: Icons.share,
              text: 'Share the link or show the QR code to your team.',
            ),
            _Step(
              icon: Icons.phone_android,
              text: 'They download Rover, tap their role card, and scan or paste your link.',
            ),
            _Step(
              icon: Icons.check_circle_outline,
              text: 'They appear in your Members tab instantly.',
            ),
            _Step(
              icon: Icons.refresh,
              text: 'Reset the link at any time to stop new joins without affecting existing members.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.text});
  final IconData icon;
  final String   text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF478DE0)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
