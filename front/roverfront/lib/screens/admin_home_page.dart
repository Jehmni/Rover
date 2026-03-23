// admin_home_page.dart
//
// Organisation admin home screen — 3 tabs:
//   Events  — create, edit, cancel, assign driver, view attendees
//   Members — all drivers and users in this org
//   Invites — generate and manage join codes

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/org_service.dart';
import '../theme/rover_theme.dart';
import '../widgets/auth_dialog.dart';
import 'user_guide_page.dart';

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
      backgroundColor: RoverColors.surface,
      appBar: AppBar(
        backgroundColor: RoverColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admin Dashboard',
              style: GoogleFonts.inter(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            if (_orgName != null)
              Text(
                _orgName!,
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const UserGuidePage(role: 'admin'),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: GoogleFonts.inter(
              fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.event, size: 20), text: 'Events'),
            Tab(icon: Icon(Icons.people, size: 20), text: 'Members'),
            Tab(icon: Icon(Icons.share, size: 20), text: 'Share'),
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
    final ev = existing;
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
          title: Text(isEdit ? 'Edit Event' : 'Create Event',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
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
                          firstDate: DateTime.now()
                              .subtract(const Duration(minutes: 55)),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365 * 2)),
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
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: RoverColors.primary),
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
                      description:  descCtrl.text.trim().isEmpty
                          ? null
                          : descCtrl.text.trim(),
                      eventType:    typeCtrl.text.trim().isEmpty
                          ? null
                          : typeCtrl.text.trim(),
                      locationName: locCtrl.text.trim().isEmpty
                          ? null
                          : locCtrl.text.trim(),
                      eventDate:    pickedDate!,
                    );
                    _snack('Event updated.', RoverColors.primary);
                  } else {
                    await EventService.createEvent(
                      name:         nameCtrl.text.trim(),
                      description:  descCtrl.text.trim().isEmpty
                          ? null
                          : descCtrl.text.trim(),
                      eventDate:    pickedDate!,
                      eventType:    typeCtrl.text.trim().isEmpty
                          ? null
                          : typeCtrl.text.trim(),
                      locationName: locCtrl.text.trim().isEmpty
                          ? null
                          : locCtrl.text.trim(),
                    );
                    _snack('Event created!', RoverColors.primary);
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
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w700)),
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
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: RoverColors.primary),
              onPressed: selectedId == null
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      setState(() => _isActing = true);
                      try {
                        await EventService.assignDriver(eventId, selectedId!);
                        _snack('Driver assigned!', RoverColors.primary);
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
      Navigator.of(context).pop();

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Attendees — $eventName',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
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
                      final name =
                          profile['full_name'] as String? ?? 'User';
                      final phone = profile['phone'] as String?;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: RoverColors.primary,
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
        content: Text(
            'This will cancel "$name". Attendees will no longer see it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isActing = true);
    try {
      await EventService.cancelEvent(eventId);
      _snack('Event cancelled.', RoverColors.secondary);
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
      backgroundColor: RoverColors.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isActing ? null : () => _showEventDialog(),
        backgroundColor: RoverColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('New Event',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_note,
                          size: 56, color: RoverColors.textSecondary),
                      const SizedBox(height: 12),
                      Text('No events yet. Tap + to create one.',
                          style: GoogleFonts.inter(
                              color: RoverColors.textSecondary, fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isCancelled
                              ? RoverColors.surfaceContainerLow
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: isCancelled
                              ? null
                              : Border(
                                  left: BorderSide(
                                      color: RoverColors.primary, width: 4),
                                ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      ev['name'] as String? ?? 'Unnamed',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: isCancelled
                                            ? RoverColors.textSecondary
                                            : RoverColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (isCancelled)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: RoverColors.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text('CANCELLED',
                                          style: GoogleFonts.inter(
                                              fontSize: 10,
                                              color: RoverColors.textSecondary,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (date != null)
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today,
                                        size: 12,
                                        color: RoverColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${date.day}/${date.month}/${date.year}  '
                                      '${date.hour.toString().padLeft(2, '0')}:'
                                      '${date.minute.toString().padLeft(2, '0')}',
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: RoverColors.textSecondary),
                                    ),
                                  ],
                                ),
                              if (ev['event_type'] != null) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: RoverColors.secondaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(ev['event_type'] as String,
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: RoverColors.secondary)),
                                ),
                              ],
                              if (ev['location_name'] != null) ...[
                                const SizedBox(height: 4),
                                Text(ev['location_name'] as String,
                                    style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: RoverColors.textSecondary)),
                              ],
                              if (!isCancelled) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.directions_bus,
                                      size: 14,
                                      color: driverName != null
                                          ? RoverColors.primary
                                          : RoverColors.secondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      driverName != null
                                          ? 'Driver: $driverName'
                                          : 'No driver assigned',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: driverName != null
                                            ? RoverColors.primary
                                            : RoverColors.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (!isCancelled) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    _ActionChip(
                                      icon: Icons.people_outline,
                                      label: 'Attendees',
                                      onPressed: _isActing
                                          ? null
                                          : () => _showAttendeesDialog(
                                                ev['id'] as int,
                                                ev['name'] as String? ??
                                                    'Event',
                                              ),
                                    ),
                                    _ActionChip(
                                      icon: Icons.directions_bus,
                                      label: 'Assign Driver',
                                      onPressed: _isActing
                                          ? null
                                          : () => _showAssignDriverDialog(
                                                ev['id'] as int,
                                                ev['name'] as String? ??
                                                    'Event',
                                              ),
                                    ),
                                    _ActionChip(
                                      icon: Icons.edit,
                                      label: 'Edit',
                                      onPressed: _isActing
                                          ? null
                                          : () => _showEventDialog(existing: ev),
                                    ),
                                    _ActionChip(
                                      icon: Icons.cancel,
                                      label: 'Cancel',
                                      danger: true,
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

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red : RoverColors.primary;
    return TextButton.icon(
      icon: Icon(icon, size: 14, color: color),
      label: Text(label,
          style: GoogleFonts.inter(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline,
                  size: 56, color: RoverColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'No members yet.\nShare the invite link from the Share tab.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: RoverColors.textSecondary, fontSize: 15, height: 1.6),
              ),
            ],
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (admins.isNotEmpty) ...[
            _sectionHeader('Administrators', Icons.manage_accounts,
                Colors.purple),
            ...admins.map((m) => _memberTile(m)),
            const SizedBox(height: 8),
          ],
          if (drivers.isNotEmpty) ...[
            _sectionHeader('Drivers', Icons.directions_bus, RoverColors.secondary),
            ...drivers.map((m) => _memberTile(m)),
            const SizedBox(height: 8),
          ],
          if (users.isNotEmpty) ...[
            _sectionHeader('Attendees', Icons.people, RoverColors.primary),
            ...users.map((m) => _memberTile(m)),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> m) {
    final name  = m['full_name'] as String? ?? 'Unknown';
    final phone = m['phone']     as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: RoverColors.primaryContainer,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: GoogleFonts.inter(
                color: RoverColors.primary, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(name,
            style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: phone != null
            ? Text(phone,
                style: GoogleFonts.inter(
                    fontSize: 12, color: RoverColors.textSecondary))
            : null,
        trailing: phone != null
            ? IconButton(
                icon: Icon(Icons.copy, size: 16, color: RoverColors.textSecondary),
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

  // M-9: realtime channel for incoming join requests
  RealtimeChannel? _requestsChannel;

  static const _baseUrl = 'https://rover.app/join/';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        OrgService.getMyOrg(),
        OrgService.getPendingRequests(),
      ]);
      if (mounted) {
        final org = results[0] as Map<String, dynamic>?;
        setState(() {
          _org             = org;
          _pendingRequests = results[1] as List<Map<String, dynamic>>;
        });

        final orgId = org?['id'] as String?;
        if (orgId != null && _requestsChannel == null) {
          _requestsChannel = OrgService.subscribeToPendingRequests(
            orgId: orgId,
            onChange: _reloadPendingRequests,
          );
        }
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

  Future<void> _reloadPendingRequests() async {
    try {
      final requests = await OrgService.getPendingRequests();
      if (mounted) setState(() => _pendingRequests = requests);
    } catch (_) {}
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: RoverColors.primary),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Request?'),
        content: Text('Reject the join request from $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reject',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
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
      return Center(
        child: Text('Could not load organisation.',
            style: GoogleFonts.inter(color: RoverColors.textSecondary)),
      );
    }

    final orgToken = _org!['org_token'] as String? ?? '';

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Heading
            Text(
              'Invite your team',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: RoverColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Anyone with this link can join ${_org!['name']} on Rover.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: RoverColors.textSecondary),
            ),
            const SizedBox(height: 24),

            // QR code card
            if (orgToken.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: QrImageView(
                  data: _inviteUrl,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
            const SizedBox(height: 20),

            // Link display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: RoverColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _inviteUrl,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: RoverColors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, size: 18, color: RoverColors.primary),
                    tooltip: 'Copy link',
                    onPressed: _copyLink,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Share button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _shareLink,
                style: FilledButton.styleFrom(
                  backgroundColor: RoverColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.share),
                label: Text('Share Invite Link',
                    style: GoogleFonts.inter(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),

            // Reset link
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isResetting ? null : _resetLink,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isResetting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.red),
                      )
                    : const Icon(Icons.refresh),
                label: Text('Reset Link (invalidates current QR)',
                    style: GoogleFonts.inter(fontSize: 13)),
              ),
            ),

            // Pending join requests
            if (_pendingRequests.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.pending_actions,
                      size: 16, color: RoverColors.secondary),
                  const SizedBox(width: 6),
                  Text(
                    'Pending Requests (${_pendingRequests.length})',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: RoverColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...(_pendingRequests.map((req) {
                final reqId  = req['id'] as int;
                final profile =
                    (req['profiles'] as Map?)?.cast<String, dynamic>() ?? {};
                final name  = profile['full_name'] as String? ?? 'Unknown';
                final phone = profile['phone']     as String?;
                final date  = req['created_at'] != null
                    ? DateTime.tryParse(req['created_at'] as String)
                    : null;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: RoverColors.primaryContainer,
                          radius: 20,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: GoogleFonts.inter(
                                color: RoverColors.primary,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              if (phone != null)
                                Text(phone,
                                    style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: RoverColors.textSecondary)),
                              if (date != null)
                                Text(
                                  'Requested ${date.day}/${date.month}/${date.year}',
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: RoverColors.textSecondary),
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: RoverColors.primary),
                          onPressed: () => _approveRequest(reqId, name),
                          child: Text('Approve',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600)),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red),
                          onPressed: () => _rejectRequest(reqId, name),
                          child: Text('Reject',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                );
              })),
            ],

            const SizedBox(height: 24),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RoverColors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w700, color: RoverColors.primary),
          ),
          const SizedBox(height: 10),
          _Step(
            icon: Icons.share,
            text: 'Share the link or show the QR code to your team.',
          ),
          _Step(
            icon: Icons.phone_android,
            text:
                'They download Rover, tap their role card, and scan or paste your link.',
          ),
          _Step(
            icon: Icons.check_circle_outline,
            text: 'They appear in your Members tab instantly.',
          ),
          _Step(
            icon: Icons.refresh,
            text:
                'Reset the link at any time to stop new joins without affecting existing members.',
          ),
        ],
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
          Icon(icon, size: 16, color: RoverColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                  fontSize: 13, color: RoverColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
