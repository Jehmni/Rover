// user_guide_page.dart
//
// Interactive in-app user guide.
// Pass [role] to pre-expand the section most relevant to the current user.
// Accessible via the help (?) icon on every major screen's AppBar.

import 'package:flutter/material.dart';

class UserGuidePage extends StatefulWidget {
  /// 'admin' | 'driver' | 'user' | null (shows all equally)
  final String? role;

  const UserGuidePage({super.key, this.role});

  @override
  State<UserGuidePage> createState() => _UserGuidePageState();
}

class _UserGuidePageState extends State<UserGuidePage> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections(widget.role);
    final filtered = _search.isEmpty
        ? sections
        : sections.where((s) {
            final q = _search.toLowerCase();
            if (s.title.toLowerCase().contains(q)) return true;
            return s.items.any((item) =>
                item.question.toLowerCase().contains(q) ||
                item.answer.toLowerCase().contains(q));
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Guide'),
        backgroundColor: const Color(0xFF478DE0),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────
          Container(
            color: const Color(0xFF478DE0),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search the guide…',
                hintStyle: const TextStyle(color: Colors.white60),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white24,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),

          // ── Role pill ─────────────────────────────────────
          if (widget.role != null && _search.isEmpty)
            Container(
              width: double.infinity,
              color: const Color(0xFFE8F4FD),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(_roleIcon(widget.role!),
                      size: 16, color: const Color(0xFF478DE0)),
                  const SizedBox(width: 6),
                  Text(
                    'Showing guide for: ${_roleLabel(widget.role!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF478DE0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // ── Sections ──────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No results found.\nTry different keywords.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) =>
                        _SectionCard(section: filtered[i], search: _search),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Section builder ────────────────────────────────────────
  List<_Section> _buildSections(String? role) {
    final all = <_Section>[
      // ── GETTING STARTED ──────────────────────────────────
      _Section(
        icon: Icons.rocket_launch_rounded,
        title: 'Getting Started',
        color: const Color(0xFF478DE0),
        initiallyExpanded: role == null,
        items: [
          _Item(
            'How do I create an account?',
            'Tap CREATE AN ACCOUNT on the login screen. Choose the card that '
            'describes how you will use Rover — Organising events, Driver, or '
            'Attending an event. Fill in your name, email, and password, then '
            'tap REGISTER.',
          ),
          _Item(
            'I registered but need to confirm my email first.',
            'Check your inbox (and spam folder) for a confirmation email. '
            'Click the link inside it, then return to Rover and sign in normally. '
            'You will be taken to Organisation Setup to complete your account.',
          ),
          _Item(
            'What is Organisation Setup?',
            'Every user must be linked to an organisation before they can use '
            'the app. Admins create a new organisation; drivers and attendees '
            'join an existing one using a QR code or invite link from their admin.',
          ),
          _Item(
            'Can I change my role later?',
            'Roles are assigned server-side when you join or create an '
            'organisation. Contact your admin if your role needs to change.',
          ),
        ],
      ),

      // ── FOR ADMINS ───────────────────────────────────────
      _Section(
        icon: Icons.admin_panel_settings_rounded,
        title: 'For Organisers (Admins)',
        color: Colors.purple,
        initiallyExpanded: role == 'admin',
        items: [
          _Item(
            'How do I set up my organisation?',
            'After registering as an organiser, you land on Organisation Setup '
            'with the Create Organisation tab open. Enter your organisation name '
            '(required), city, country, and type, then tap CREATE ORGANISATION. '
            'You immediately become the admin.',
          ),
          _Item(
            'How do I create an event?',
            'On your Admin Dashboard, go to the Events tab and tap the + button '
            'in the top-right corner. Fill in the event name, type, description, '
            'date & time (must be at least 1 hour in the future), venue name, '
            'and GPS coordinates of the venue. Tap CREATE EVENT.',
          ),
          _Item(
            'How do I get GPS coordinates for a venue?',
            'Open Google Maps, long-press the venue location on the map, and '
            'copy the coordinates shown at the top of the screen '
            '(e.g. 51.5074, -0.1278). Enter latitude first, then longitude.',
          ),
          _Item(
            'How do I assign a driver to an event?',
            'On the Events tab, tap Assign Driver next to the event. A list of '
            'your organisation\'s drivers appears. Tap the driver you want. '
            'The driver must have already joined your organisation to appear here.',
          ),
          _Item(
            'How do I invite members?',
            'Go to the Share tab on your Admin Dashboard. You will see a QR '
            'code and a Share Link button. Send the link via WhatsApp, SMS, or '
            'email, or show the QR code for members to scan. Both methods take '
            'the member directly into Rover and pre-fill the join screen.',
          ),
          _Item(
            'How do I reset my invite code?',
            'On the Share tab, tap Reset Code. A new invite token is generated '
            'instantly. All previously shared QR codes and links are immediately '
            'invalidated. Use this if you shared your link with the wrong person.',
          ),
          _Item(
            'How do I approve join requests?',
            'Members who cannot find your QR code can search for your '
            'organisation and send a join request. You will see pending requests '
            'on the Share tab under Pending Join Requests. Tap Approve to add '
            'them, or Reject to decline.',
          ),
          _Item(
            'How do I edit or cancel an event?',
            'On the Events tab, tap the event to expand it, then tap Edit to '
            'change any field, or Cancel to mark the event as cancelled. '
            'Cancelled events remain visible but are clearly marked.',
          ),
          _Item(
            'Where can I see my members?',
            'Go to the Members tab on your Admin Dashboard. All drivers and '
            'attendees in your organisation are listed with their role and '
            'join date.',
          ),
        ],
      ),

      // ── FOR DRIVERS ──────────────────────────────────────
      _Section(
        icon: Icons.directions_bus_rounded,
        title: 'For Drivers',
        color: Colors.green,
        initiallyExpanded: role == 'driver',
        items: [
          _Item(
            'How do I join my organisation?',
            'Ask your admin to share the invite link or QR code with you. '
            'On the Welcome screen, select I\'m a driver, then complete '
            'registration. On Organisation Setup, scan the QR code or paste '
            'the link and tap JOIN ORGANISATION.',
          ),
          _Item(
            'Where do I see my assigned events?',
            'On your Driver Dashboard, your assigned events are listed with '
            'the event name and date. If the list is empty, your admin has '
            'not yet assigned any events to you — contact them to confirm.',
          ),
          _Item(
            'How do I start a pickup route?',
            'Make sure your phone\'s GPS is turned on. Find the event on your '
            'Driver Dashboard and tap Start Route. The app reads your location, '
            'fetches all pickup requests, and calculates the most efficient '
            'order automatically. The pickup list appears below.',
          ),
          _Item(
            'How do I use the map?',
            'Once a route is started, tap View Map (bottom-right). The map '
            'shows a green car icon for your position, numbered blue circles '
            'for each pending stop, and grey checks for completed stops. '
            'Use the top-right icons to centre on yourself or fit all stops '
            'on screen. Tap any row in the bottom list to zoom in on that stop.',
          ),
          _Item(
            'How do I mark a passenger as picked up?',
            'Use the two-step flow: first tap On My Way (car icon) when you '
            'are heading to them — their pin turns blue and they see "En Route". '
            'Then tap Done (green tick) once you have collected them — their '
            'pin turns grey and they are crossed off the list.',
          ),
          _Item(
            'Can I recalculate the route mid-trip?',
            'Yes. On your Driver Dashboard, tap Re-route on the active event. '
            'The system recalculates from your current position using only the '
            'remaining (non-completed) stops.',
          ),
          _Item(
            'The map shows my car in the wrong place.',
            'GPS accuracy depends on your surroundings. Indoors or in areas '
            'with poor signal, your position may be off by several metres. '
            'Move outdoors or wait a few seconds for the GPS to stabilise.',
          ),
        ],
      ),

      // ── FOR ATTENDEES ────────────────────────────────────
      _Section(
        icon: Icons.people_rounded,
        title: 'For Attendees',
        color: const Color(0xFF478DE0),
        initiallyExpanded: role == 'user',
        items: [
          _Item(
            'How do I join my organisation?',
            'Ask your admin to share the invite link or QR code. On the '
            'Welcome screen, select I\'m attending an event, complete '
            'registration, then scan the QR or paste the link on Organisation '
            'Setup and tap JOIN ORGANISATION.',
          ),
          _Item(
            'How do I find events?',
            'Your home screen lists all upcoming events in your organisation. '
            'Use the search bar at the top to filter by name or type. '
            'Pull down on the list to refresh.',
          ),
          _Item(
            'What does subscribing to an event mean?',
            'Subscribing tells the admin you plan to attend. You must subscribe '
            'before you can request a pickup. Tap Subscribe on the event detail '
            'page. Tap Unsubscribe if your plans change.',
          ),
          _Item(
            'How do I request a pickup?',
            'First subscribe to the event. Then tap Request Pickup on the event '
            'detail page. The app asks for your location — tap Allow. Stand at '
            'the exact spot where you want to be collected, then confirm. '
            'The button changes to "Pickup Requested" to confirm it worked.',
          ),
          _Item(
            'How do I track my driver?',
            'On the event detail page, once a driver has been assigned and '
            'started the route, an ETA card appears at the bottom. It shows '
            'your stop number, minutes until the driver reaches you, and your '
            'current status (Waiting / En Route / Picked Up). This updates live.',
          ),
          _Item(
            'The "Request Pickup" button is greyed out.',
            'You must subscribe to the event first. The button only becomes '
            'active after you tap Subscribe. If you are subscribed and it is '
            'still grey, go back and re-open the event to refresh.',
          ),
          _Item(
            'The ETA card is not showing.',
            'The ETA card appears only when all three conditions are met: '
            '(1) you have a pickup request, (2) the admin has assigned a driver, '
            'and (3) the driver has started the route. If any step is pending, '
            'the card will not appear yet.',
          ),
        ],
      ),

      // ── JOINING AN ORG ───────────────────────────────────
      _Section(
        icon: Icons.link_rounded,
        title: 'Joining an Organisation',
        color: Colors.teal,
        initiallyExpanded: false,
        items: [
          _Item(
            'How do I join via QR code?',
            'Ask your admin to open the Share tab and show you the QR code. '
            'In Rover, on the Join Organisation screen, tap SCAN QR CODE. '
            'Point your camera at the code — the app reads it and joins you '
            'automatically. Grant camera permission if prompted.',
          ),
          _Item(
            'How do I join via a share link?',
            'Your admin sends you a link (e.g. via WhatsApp or email). '
            'Option A: tap the link directly — if Rover is installed it opens '
            'the app and pre-fills the join screen; tap JOIN ORGANISATION. '
            'Option B: copy the link, open Rover, paste it into the Invite '
            'Link field on the Join Organisation screen, and tap JOIN.',
          ),
          _Item(
            'I don\'t have a QR code or link. What do I do?',
            'On the Join Organisation screen, scroll to the bottom and tap '
            '"Can\'t find your link? Search for your organisation". Type the '
            'name or city of your organisation, find it in the results, and '
            'tap Request. Your admin will be notified and can approve you from '
            'the Share tab. Wait for approval before trying to log in again.',
          ),
          _Item(
            'I get "That doesn\'t look like a Rover invite code".',
            'The QR code or link you used is invalid or has expired. Ask your '
            'admin to reshare the invite from the Share tab. If they recently '
            'reset the code, all old links are invalidated and a fresh share '
            'is needed.',
          ),
          _Item(
            'Conference organisations — why can\'t I join?',
            'Conference orgs only allow pre-registered email addresses. If '
            'your email is not on the attendee list, access will be denied. '
            'Contact your event organiser to have your email added.',
          ),
        ],
      ),

      // ── ACCOUNT ──────────────────────────────────────────
      _Section(
        icon: Icons.manage_accounts_rounded,
        title: 'Account & Sign In',
        color: Colors.orange,
        initiallyExpanded: false,
        items: [
          _Item(
            'How do I sign in?',
            'Open Rover and enter your email and password on the login screen. '
            'Tap LOGIN.',
          ),
          _Item(
            'I forgot my password.',
            'Tap Forgot Password? on the login screen. Enter your email and '
            'tap Send. Check your inbox for a reset link and follow the '
            'instructions to set a new password.',
          ),
          _Item(
            'How do I sign out?',
            'Tap the logout icon (arrow pointing right or out) in the top-right '
            'corner of any home screen.',
          ),
          _Item(
            'I confirmed my email but cannot sign in.',
            'Make sure you are using the same email address you registered with. '
            'Passwords are case-sensitive and must be at least 8 characters. '
            'If you still cannot sign in, use Forgot Password? to reset it.',
          ),
        ],
      ),

      // ── NOTIFICATIONS ────────────────────────────────────
      _Section(
        icon: Icons.notifications_rounded,
        title: 'Notifications',
        color: Colors.red,
        initiallyExpanded: false,
        items: [
          _Item(
            'I am not receiving notifications.',
            'Check that you allowed notification permission when the app first '
            'asked. On Android, go to Settings → Apps → Rover → Notifications '
            'and ensure they are enabled. Notifications are sent when the driver '
            'starts a route — you must have an active pickup request.',
          ),
          _Item(
            'When does Rover send me a notification?',
            'A push notification is sent to the first passenger in the pickup '
            'order when the driver starts a route. Further notifications for '
            'status changes (en route, picked up) are visible in the app via '
            'the live ETA card.',
          ),
        ],
      ),

      // ── TROUBLESHOOTING ──────────────────────────────────
      _Section(
        icon: Icons.build_rounded,
        title: 'Troubleshooting',
        color: Colors.grey,
        initiallyExpanded: false,
        items: [
          _Item(
            'The app shows a loading spinner and nothing happens.',
            'Check your internet connection. Rover requires an active connection '
            'for all features. Close and reopen the app if the spinner persists.',
          ),
          _Item(
            'My pickup location was recorded in the wrong place.',
            'Contact your admin to cancel your request. Then move to the correct '
            'spot, reopen the event, and tap Request Pickup again. Make sure '
            'your phone\'s GPS is turned on before tapping.',
          ),
          _Item(
            'I tapped "Start Route" but got an error.',
            'Ensure your GPS is on and location permission is granted. Also '
            'confirm that attendees have submitted pickup requests for the event '
            '— starting a route with no requests returns an empty list.',
          ),
          _Item(
            'The app is slow or freezes.',
            'Force-close the app and reopen it. If the issue continues, '
            'check your mobile data or Wi-Fi connection. The app relies on '
            'a live connection for real-time updates.',
          ),
          _Item(
            'I need help not covered here.',
            'Contact your organisation admin first — they can resolve most '
            'access and membership issues. For app bugs or technical problems, '
            'contact your Rover administrator.',
          ),
        ],
      ),
    ];

    // Role-specific sections first, then the rest
    if (role != null) {
      all.sort((a, b) {
        final aMatch = a.initiallyExpanded ? 0 : 1;
        final bMatch = b.initiallyExpanded ? 0 : 1;
        return aMatch.compareTo(bMatch);
      });
    }

    return all;
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':  return 'Organiser';
      case 'driver': return 'Driver';
      default:       return 'Attendee';
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'admin':  return Icons.admin_panel_settings_rounded;
      case 'driver': return Icons.directions_bus_rounded;
      default:       return Icons.people_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────
class _Section {
  final IconData icon;
  final String   title;
  final Color    color;
  final bool     initiallyExpanded;
  final List<_Item> items;

  const _Section({
    required this.icon,
    required this.title,
    required this.color,
    required this.initiallyExpanded,
    required this.items,
  });
}

class _Item {
  final String question;
  final String answer;
  const _Item(this.question, this.answer);
}

// ─────────────────────────────────────────────────────────────
// Section card widget
// ─────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.search});
  final _Section section;
  final String   search;

  @override
  Widget build(BuildContext context) {
    // When searching, show items that match; otherwise show all
    final items = search.isEmpty
        ? section.items
        : section.items.where((item) {
            final q = search.toLowerCase();
            return item.question.toLowerCase().contains(q) ||
                item.answer.toLowerCase().contains(q);
          }).toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: section.initiallyExpanded || search.isNotEmpty,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: section.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(section.icon, color: section.color, size: 20),
          ),
          title: Text(
            section.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: section.color,
            ),
          ),
          children: items
              .map((item) => _GuideItem(item: item, search: search))
              .toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Individual Q&A item
// ─────────────────────────────────────────────────────────────
class _GuideItem extends StatelessWidget {
  const _GuideItem({required this.item, required this.search});
  final _Item  item;
  final String search;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 20),
      childrenPadding:
          const EdgeInsets.fromLTRB(20, 0, 20, 16),
      leading: const Icon(Icons.help_outline, size: 18, color: Colors.grey),
      title: Text(
        item.question,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F8FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            item.answer,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Color(0xFF444444),
            ),
          ),
        ),
      ],
    );
  }
}
