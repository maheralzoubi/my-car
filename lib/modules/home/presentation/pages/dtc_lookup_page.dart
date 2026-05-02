import 'package:flutter/material.dart';

import '../../../../core/services/dtc_repository.dart';

class DtcLookupPage extends StatefulWidget {
  const DtcLookupPage({super.key});

  @override
  State<DtcLookupPage> createState() => _DtcLookupPageState();
}

class _DtcLookupPageState extends State<DtcLookupPage> {
  final _controller = TextEditingController();
  final _repository = DtcRepository();

  String? _result;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = 'Please enter a DTC code.';
        _result = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final description = await _repository.getDtcDescription(code);
      setState(() {
        if (description == null || description.isEmpty) {
          _result = null;
          _error = 'No description found for code "$code".';
        } else {
          _result = description;
          _error = null;
        }
      });
    } catch (e) {
      setState(() {
        _result = null;
        _error = 'Failed to fetch description. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DTC Lookup'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Enter DTC code (e.g. P0300)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _lookup,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Get Description'),
              ),
            ),
            const SizedBox(height: 24),
            if (_result != null) ...[
              const Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _result!,
                style: const TextStyle(fontSize: 15),
              ),
            ] else if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

