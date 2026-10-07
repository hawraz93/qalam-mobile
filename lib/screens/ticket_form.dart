import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

/// Opens a new IT ticket. Guests fill in who they are; signed-in users do not.
class TicketFormScreen extends StatefulWidget {
  const TicketFormScreen({super.key});

  @override
  State<TicketFormScreen> createState() => _TicketFormScreenState();
}

class _TicketFormScreenState extends State<TicketFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _category = 'other';
  String _priority = 'medium';
  bool _busy = false;
  String? _sentTicketNo;

  bool get _guest => !api.isSignedIn;

  @override
  void dispose() {
    for (final controller in [_name, _email, _phone, _title, _description]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final body = await api.post('/tickets/submit', {
        if (_guest) 'requester_name': _name.text.trim(),
        if (_guest) 'requester_email': _email.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'requester_phone': _phone.text.trim(),
        'category': _category,
        'priority': _priority,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
      });
      if (mounted) setState(() => _sentTicketNo = body['data']['ticket_no']?.toString() ?? '');
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? value, {int min = 1}) {
    return (value ?? '').trim().length < min ? S.of(context).t('required') : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    const border = OutlineInputBorder();

    if (_sentTicketNo != null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.t('new_ticket'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 72, color: Colors.green),
                const SizedBox(height: 16),
                Text(s.t('ticket_sent'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(_sentTicketNo!, style: Theme.of(context).textTheme.headlineSmall),
                if (_guest) ...[
                  const SizedBox(height: 12),
                  Text(s.t('ticket_sent_guest'), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('OK')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.t('new_ticket'))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_guest) ...[
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: s.t('your_name'), border: border),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: s.t('email'), border: border),
                validator: (value) => (value ?? '').contains('@') ? null : s.t('required'),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _phone,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: s.t('phone'), border: border),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(labelText: s.t('category'), border: border),
              items: [
                for (final category in const ['hardware', 'software', 'network', 'account', 'printer', 'other'])
                  DropdownMenuItem(value: category, child: Text(s.t('cat_$category'))),
              ],
              onChanged: (value) => setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: InputDecoration(labelText: s.t('priority'), border: border),
              items: [
                for (final priority in const ['low', 'medium', 'high', 'urgent'])
                  DropdownMenuItem(value: priority, child: Text(s.t(priority))),
              ],
              onChanged: (value) => setState(() => _priority = value ?? _priority),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(labelText: s.t('ticket_title'), border: border),
              validator: (value) => _required(value, min: 4),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(labelText: s.t('ticket_description'), border: border),
              validator: (value) => _required(value, min: 10),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.send),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(s.t('send_ticket')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
