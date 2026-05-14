import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

const _bg           = Color(0xFF000000);
const _iosBlue      = Color(0xFF007AFF);
const _iosGreen     = Color(0xFF34C759);
const _iosLabel     = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _iosRed       = Color(0xFFFF3B30);

class ContactDialogs {
  static void showNewContact(BuildContext context, {String? initialPhone, VoidCallback? onDone}) {
    final nameCtrl = TextEditingController();
    final List<TextEditingController> phoneCtrls = [
      TextEditingController(text: initialPhone ?? '')
    ];

    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: CupertinoAlertDialog(
            title: const Text('New Contact'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoTextField(
                    controller: nameCtrl,
                    placeholder: 'Name',
                    placeholderStyle: const TextStyle(color: _iosSecondary),
                    style: const TextStyle(color: _iosLabel),
                    decoration: BoxDecoration(
                      color: _bg.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...phoneCtrls.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final ctrl = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoTextField(
                              controller: ctrl,
                              placeholder: 'Phone',
                              keyboardType: TextInputType.phone,
                              placeholderStyle: const TextStyle(color: _iosSecondary),
                              style: const TextStyle(color: _iosLabel),
                              decoration: BoxDecoration(
                                color: _bg.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          if (phoneCtrls.length > 1)
                            GestureDetector(
                              onTap: () => setDialogState(() => phoneCtrls.removeAt(idx)),
                              child: const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(CupertinoIcons.minus_circle_fill, color: _iosRed, size: 22),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  GestureDetector(
                    onTap: () => setDialogState(() => phoneCtrls.add(TextEditingController())),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.plus_circle_fill, color: _iosGreen, size: 22),
                          const SizedBox(width: 8),
                          const Text('add phone', style: TextStyle(color: _iosLabel, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel', style: TextStyle(color: _iosBlue)),
                onPressed: () => Navigator.pop(ctx),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final phones = phoneCtrls
                      .map((c) => c.text.trim())
                      .where((t) => t.isNotEmpty)
                      .map((t) => Phone(number: t))
                      .toList();

                  if (name.isNotEmpty && phones.isNotEmpty) {
                    final newContact = Contact(
                      name: Name(first: name),
                      phones: phones,
                    );
                    await FlutterContacts.create(newContact);
                    Navigator.pop(ctx);
                    if (onDone != null) onDone();
                  }
                },
                child: const Text('Done', style: TextStyle(color: _iosBlue, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> showEditContact(BuildContext context, Contact contact, {VoidCallback? onDone}) async {
    final fullContact = await FlutterContacts.get(
      contact.id!,
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    
    if (fullContact == null) return;

    final nameCtrl = TextEditingController(text: fullContact.name?.first ?? '');
    final List<TextEditingController> phoneCtrls = fullContact.phones
        .map((p) => TextEditingController(text: p.number))
        .toList();
    
    if (phoneCtrls.isEmpty) phoneCtrls.add(TextEditingController());

    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: CupertinoAlertDialog(
            title: const Text('Edit Contact'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoTextField(
                    controller: nameCtrl,
                    placeholder: 'Name',
                    placeholderStyle: const TextStyle(color: _iosSecondary),
                    style: const TextStyle(color: _iosLabel),
                    decoration: BoxDecoration(
                      color: _bg.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...phoneCtrls.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final ctrl = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoTextField(
                              controller: ctrl,
                              placeholder: 'Phone',
                              keyboardType: TextInputType.phone,
                              placeholderStyle: const TextStyle(color: _iosSecondary),
                              style: const TextStyle(color: _iosLabel),
                              decoration: BoxDecoration(
                                color: _bg.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          if (phoneCtrls.length > 1)
                            GestureDetector(
                              onTap: () => setDialogState(() => phoneCtrls.removeAt(idx)),
                              child: const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(CupertinoIcons.minus_circle_fill, color: _iosRed, size: 22),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  GestureDetector(
                    onTap: () => setDialogState(() => phoneCtrls.add(TextEditingController())),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.plus_circle_fill, color: _iosGreen, size: 22),
                          const SizedBox(width: 8),
                          const Text('add phone', style: TextStyle(color: _iosLabel, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel', style: TextStyle(color: _iosBlue)),
                onPressed: () => Navigator.pop(ctx),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final phones = phoneCtrls
                      .map((c) => c.text.trim())
                      .where((t) => t.isNotEmpty)
                      .map((t) => Phone(number: t))
                      .toList();

                  if (name.isNotEmpty && phones.isNotEmpty) {
                    final updatedContact = fullContact.copyWith(
                      name: fullContact.name?.copyWith(first: name) ?? Name(first: name),
                      phones: phones,
                    );
                    await FlutterContacts.update(updatedContact);
                    Navigator.pop(ctx);
                    if (onDone != null) onDone();
                  }
                },
                child: const Text('Done', style: TextStyle(color: _iosBlue, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
