import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _verificationId, _error;
  bool _busy = false;

  Future<void> _send() async {
    if (!AuthService.isValidTz(_phone.text)) {
      setState(() => _error = 'Enter a Tanzanian mobile number, like 0712 345 678.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await AuthService.sendCode(
      _phone.text,
      onCode: (id) => setState(() {
        _verificationId = id;
        _busy = false;
      }),
      onError: (m) => setState(() {
        _error = m;
        _busy = false;
      }),
      onAutoSignIn: () {},
    );
  }

  Future<void> _confirm() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the SMS.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.confirm(_verificationId!, _code.text.trim());
    } catch (e) {
      setState(() {
        _error = 'That code is wrong or expired. Check the SMS or send a new code.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sent = _verificationId != null;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 40),
          CircleAvatar(
            radius: 28,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text('L', style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 20),
          Text('Anything you need, brought to your door.',
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(sent ? 'We sent a 6-digit code to ${AuthService.normalize(_phone.text)}.' : 'Sign in with your phone number. We will send you a code by SMS.'),
          const SizedBox(height: 24),
          if (!sent)
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '0712 345 678', prefixIcon: Icon(Icons.phone)),
            )
          else
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'SMS code'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : (sent ? _confirm : _send),
            child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(sent ? 'Confirm' : 'Send code'),
          ),
          if (sent)
            TextButton(
              onPressed: _busy ? null : () => setState(() => _verificationId = null),
              child: const Text('Use a different number'),
            ),
        ]),
      ),
    );
  }
}
