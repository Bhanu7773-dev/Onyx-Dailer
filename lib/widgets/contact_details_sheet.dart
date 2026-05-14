import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavedialer/screens/call_screen.dart';
import 'package:wavedialer/services/telecom_service.dart';

const _bg           = Color(0xFF1C1C1E);
const _card         = Color(0xFF2C2C2E);
const _iosBlue      = Color(0xFF007AFF);
const _iosGreen     = Color(0xFF34C759);
const _iosLabel     = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _iosTertiary  = Color(0xFF48484A);
const _separator    = Color(0xFF38383A);
const _iosRed       = Color(0xFFFF3B30);

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
    final logs = await CallLog.get();
    
    // Normalize target phone
    final targetPhone = widget.phone.replaceAll(RegExp(r'\D'), '');
    
    final filtered = logs.where((log) {
      final logPhone = (log.number ?? '').replaceAll(RegExp(r'\D'), '');
      return logPhone.isNotEmpty && (logPhone.contains(targetPhone) || targetPhone.contains(logPhone));
    }).toList();

    if (mounted) setState(() => _history = filtered);
  }

  void _dial() {
    HapticFeedback.lightImpact();
    TelecomService.makeCall(widget.phone);
    Navigator.pop(context); // close sheet
    Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(initialNumber: widget.phone)));
  }

  Future<void> _openWhatsApp() async {
    HapticFeedback.selectionClick();
    final url = Uri.parse('https://wa.me/${widget.phone.replaceAll(RegExp(r'\D'), '')}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openSms() async {
    HapticFeedback.selectionClick();
    final url = Uri.parse('sms:${widget.phone}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  IconData _callTypeIcon(CallType? type) {
    switch (type) {
      case CallType.incoming: return Icons.call_received_rounded;
      case CallType.outgoing: return Icons.call_made_rounded;
      case CallType.missed: return Icons.call_missed_rounded;
      case CallType.rejected: return Icons.phone_disabled_rounded;
      case CallType.blocked: return Icons.block_rounded;
      default: return Icons.call_rounded;
    }
  }

  String _callTypeLabel(CallType? type) {
    switch (type) {
      case CallType.incoming: return 'Incoming';
      case CallType.outgoing: return 'Outgoing';
      case CallType.missed: return 'Missed';
      case CallType.rejected: return 'Rejected';
      case CallType.blocked: return 'Blocked';
      default: return 'Call';
    }
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && now.day == dt.day) {
      return DateFormat('h:mm a').format(dt);
    } else if (diff.inDays < 7) {
      return DateFormat('EEEE').format(dt); // e.g. Monday
    } else {
      return DateFormat('MMM d').format(dt); // e.g. Oct 12
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds == 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '$m min ${s > 0 ? '$s sec' : ''}';
    return '$s sec';
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.trim().isEmpty ? '#' : widget.name.trim()[0].toUpperCase();
    final aColor = widget.avatarColor ?? _iosTertiary;
    final aText = widget.avatarTextColor ?? _iosLabel;

    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 40, height: 5,
            decoration: BoxDecoration(
              color: _iosSecondary.withOpacity(0.4),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // Avatar
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: aColor, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(initial, style: TextStyle(color: aText, fontSize: 36, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 12),

          // Name & Number
          Text(
            widget.name,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: _iosLabel),
          ),
          const SizedBox(height: 4),
          Text(
            widget.phone,
            style: const TextStyle(fontSize: 16, color: _iosSecondary),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _actionBtn(const Icon(Icons.call_rounded, color: _iosBlue, size: 24), 'Call', _dial),
                const SizedBox(width: 12),
                _actionBtn(const Icon(Icons.message_rounded, color: _iosBlue, size: 24), 'Message', _openSms),
                const SizedBox(width: 12),
                _actionBtn(const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366), size: 24), 'WhatsApp', _openWhatsApp, color: const Color(0xFF25D366)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // History Section Header
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('RECENT CALLS', style: TextStyle(color: _iosSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ),
          ),

          // History List
          Expanded(
            child: _history == null
                ? const Center(child: CircularProgressIndicator(color: _iosBlue))
                : _history!.isEmpty
                    ? const Center(child: Text('No recent history', style: TextStyle(color: _iosSecondary, fontSize: 15)))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 40),
                        itemCount: _history!.length,
                        itemBuilder: (ctx, i) {
                          final log = _history![i];
                          final missed = log.callType == CallType.missed || log.callType == CallType.rejected;
                          final color = missed ? _iosRed : _iosSecondary;
                          final isLast = i == _history!.length - 1;

                          return Container(
                            color: _bg, // iOS list bg
                            padding: const EdgeInsets.only(left: 24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                              decoration: BoxDecoration(
                                border: isLast ? null : const Border(bottom: BorderSide(color: _separator, width: 0.5)),
                              ),
                              child: Row(
                                children: [
                                  Icon(_callTypeIcon(log.callType), color: color, size: 16),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_callTypeLabel(log.callType), style: TextStyle(color: color, fontSize: 16)),
                                        if (_formatDuration(log.duration).isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(_formatDuration(log.duration), style: const TextStyle(color: _iosSecondary, fontSize: 13)),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(_formatTime(log.timestamp), style: const TextStyle(color: _iosSecondary, fontSize: 14)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(Widget iconWidget, String label, VoidCallback onTap, {Color color = _iosBlue}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              iconWidget,
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
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
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.85,
      child: ContactDetailsSheet(
        name: name,
        phone: phone,
        avatarColor: avatarColor,
        avatarTextColor: avatarTextColor,
      ),
    ),
  );
}
