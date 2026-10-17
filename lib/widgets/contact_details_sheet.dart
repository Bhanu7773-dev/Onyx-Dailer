import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavedialer/services/telecom_service.dart';

const _kSheetBg = Color(0xFF111419);
const _kHandleColor = Color(0xFF353E4A);
const _kAvatarBg = Color(0xFF1E2632);
const _kCardBg = Color(0xFF161D26);
const _kCallBg = Color(0xFF8AB4F8);
const _kCallIconColor = Color(0xFF09182C);
const _kTextWhite = Color(0xFFFFFFFF);
const _kTextMuted = Color(0xFF8E9CAE);
const _kCoralRed = Color(0xFFFF7769);
const _kSeparator = Color(0xFF1C232E);

class ContactDetailsSheet extends StatefulWidget {
  final String name;
  final String phone;
  final Color? avatarColor;
  final Color? avatarTextColor;

  const ContactDetailsSheet({
    super.key,
    required this.name,
    required this.phone,
    this.avatarColor,
    this.avatarTextColor,
  });

  @override
  State<ContactDetailsSheet> createState() => _ContactDetailsSheetState();
}

class _ContactDetailsSheetState extends State<ContactDetailsSheet> {
  List<CallLogEntry>? _history;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final logs = await CallLog.get();
      final targetDigits = widget.phone.replaceAll(RegExp(r'\D'), '');
      final targetLast7 = targetDigits.length >= 7
          ? targetDigits.substring(targetDigits.length - 7)
          : targetDigits;
      final targetName = widget.name.trim().toLowerCase();

      final filtered = logs.where((log) {
        final logDigits = (log.number ?? '').replaceAll(RegExp(r'\D'), '');
        final logName = (log.name ?? '').trim().toLowerCase();

        // 1. Phone number match
        if (targetDigits.isNotEmpty && logDigits.isNotEmpty) {
          if (targetDigits == logDigits) return true;
          if (targetDigits.contains(logDigits) || logDigits.contains(targetDigits)) return true;
          if (targetLast7.isNotEmpty && logDigits.endsWith(targetLast7)) return true;
        }

        // 2. Name match (if name is valid and not a number)
        if (targetName.isNotEmpty &&
            logName.isNotEmpty &&
            targetName != 'unknown' &&
            targetName == logName) {
          return true;
        }

        return false;
      }).toList();

      filtered.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

      if (mounted) setState(() => _history = filtered);
    } catch (e) {
      debugPrint('Error fetching call history: $e');
      if (mounted) setState(() => _history = []);
    }
  }

  void _dial() {
    HapticFeedback.lightImpact();
    final nav = Navigator.of(context);
    final ctx = nav.context;
    nav.pop();
    TelecomService.handleOutgoingCall(ctx, widget.phone);
  }

  String _prepareWhatsAppNumber(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }
    if (digits.length == 10 && RegExp(r'^[6-9]').hasMatch(digits)) {
      digits = '91$digits';
    }
    return digits;
  }

  Future<void> _openWhatsApp() async {
    HapticFeedback.selectionClick();
    final cleanNumber = _prepareWhatsAppNumber(widget.phone);
    if (cleanNumber.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid phone number for WhatsApp'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    bool launched = false;

    // Strategy 1: Direct native WhatsApp app URI
    try {
      final nativeUri = Uri.parse('whatsapp://send?phone=$cleanNumber');
      launched = await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    // Strategy 2: Universal wa.me URL
    if (!launched) {
      try {
        final webUri = Uri.parse('https://wa.me/$cleanNumber');
        launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    // Strategy 3: WhatsApp API endpoint
    if (!launched) {
      try {
        final apiUri = Uri.parse('https://api.whatsapp.com/send?phone=$cleanNumber');
        launched = await launchUrl(apiUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp. Please check if WhatsApp is installed.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openSms() async {
    HapticFeedback.selectionClick();
    final phone = widget.phone.trim();
    if (phone.isEmpty) return;

    bool launched = false;

    // Strategy 1: Standard SMS URI (sms:<number>)
    try {
      final smsUri = Uri(scheme: 'sms', path: phone);
      launched = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    // Strategy 2: Direct Uri.parse
    if (!launched) {
      try {
        final directUri = Uri.parse('sms:$phone');
        launched = await launchUrl(directUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    // Strategy 3: smsto: scheme
    if (!launched) {
      try {
        final smstoUri = Uri(scheme: 'smsto', path: phone);
        launched = await launchUrl(smstoUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open SMS app'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatCallDate(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(itemDate).inDays;

    if (diffDays == 0) {
      return 'Today';
    } else if (diffDays == 1) {
      return 'Yesterday';
    } else if (diffDays > 1 && diffDays < 7) {
      return DateFormat('EEEE').format(dt); // e.g. Friday, Thursday
    } else {
      return DateFormat('MMM d').format(dt); // e.g. Oct 12
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) {
      return '$m min${s > 0 ? ' $s sec' : ''}';
    }
    return '$s sec';
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.trim().isEmpty
        ? (widget.phone.trim().isNotEmpty ? '#' : '?')
        : widget.name.trim()[0].toUpperCase();

    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.82,
      decoration: const BoxDecoration(
        color: _kSheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 18),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: _kHandleColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Avatar circle
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: widget.avatarColor ?? _kAvatarBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                color: widget.avatarTextColor ?? _kTextWhite,
                fontSize: 32,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Contact Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.name.trim().isNotEmpty ? widget.name : widget.phone,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _kTextWhite,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Phone Number
          Text(
            widget.phone,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: _kTextMuted,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 22),

          // Action buttons row: Call, Message, WhatsApp
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: const Icon(Icons.call_rounded, color: _kCallIconColor, size: 24),
                    label: 'Call',
                    textColor: _kCallIconColor,
                    bgColor: _kCallBg,
                    onTap: _dial,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 22),
                    label: 'Message',
                    textColor: Colors.white,
                    bgColor: _kCardBg,
                    hasBorder: true,
                    onTap: _openSms,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 23),
                    label: 'WhatsApp',
                    textColor: Colors.white,
                    bgColor: _kCardBg,
                    hasBorder: true,
                    onTap: _openWhatsApp,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section header: RECENT CALLS
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'RECENT CALLS',
                style: TextStyle(
                  color: _kTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // History list
          Expanded(
            child: _history == null
                ? const Center(child: CircularProgressIndicator(color: _kCallBg))
                : _history!.isEmpty
                    ? const Center(
                        child: Text(
                          'No recent call history',
                          style: TextStyle(color: _kTextMuted, fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(top: 4, bottom: 32),
                        itemCount: _history!.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          thickness: 0.6,
                          color: _kSeparator,
                          indent: 24,
                          endIndent: 24,
                        ),
                        itemBuilder: (context, index) {
                          final log = _history![index];
                          return _buildCallLogItem(log);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required Widget icon,
    required String label,
    required Color textColor,
    required Color bgColor,
    bool hasBorder = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            border: hasBorder
                ? Border.all(color: Colors.white.withValues(alpha: 0.05))
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallLogItem(CallLogEntry log) {
    final isMissed = log.callType == CallType.missed;
    final isDeclined = log.callType == CallType.rejected || log.callType == CallType.blocked;
    final isOutgoing = log.callType == CallType.outgoing;

    final IconData arrowIcon;
    final Color arrowColor;
    final String labelText;
    final Color labelColor;

    if (isMissed) {
      arrowIcon = Icons.south_west_rounded;
      arrowColor = _kCoralRed;
      labelText = 'Missed';
      labelColor = _kCoralRed;
    } else if (isDeclined) {
      arrowIcon = Icons.south_west_rounded;
      arrowColor = _kCoralRed;
      labelText = 'Declined';
      labelColor = _kCoralRed;
    } else if (isOutgoing) {
      arrowIcon = Icons.north_east_rounded;
      arrowColor = _kTextMuted;
      labelText = 'Outgoing';
      labelColor = Colors.white;
    } else {
      arrowIcon = Icons.south_west_rounded;
      arrowColor = _kTextMuted;
      labelText = 'Incoming';
      labelColor = Colors.white;
    }

    final durationStr = _formatDuration(log.duration);
    final dateStr = _formatCallDate(log.timestamp);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _dial();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        child: Row(
          children: [
            // Direction Arrow
            SizedBox(
              width: 24,
              child: Icon(arrowIcon, color: arrowColor, size: 16),
            ),
            const SizedBox(width: 14),

            // Call Type & Duration
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labelText,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (durationStr.isNotEmpty && !isMissed && !isDeclined)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        durationStr,
                        style: const TextStyle(
                          color: _kTextMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Day / Date
            Text(
              dateStr,
              style: const TextStyle(
                color: _kTextMuted,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showContactDetails(BuildContext context, {
  required String name,
  required String phone,
  Color? avatarColor,
  Color? avatarTextColor,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => ContactDetailsSheet(
      name: name,
      phone: phone,
      avatarColor: avatarColor,
      avatarTextColor: avatarTextColor,
    ),
  );
}
