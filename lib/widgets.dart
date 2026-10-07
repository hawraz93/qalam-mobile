import 'package:flutter/material.dart';

import 'api.dart';
import 'strings.dart';

const brandColor = Color(0xFF910051);

String errorText(BuildContext context, Object error) {
  if (error is ApiException && error.status == 0) return S.of(context).t('network');
  return error.toString();
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "2026-10-05T09:30:00+03:00" -> "2026-10-05 09:30" in the phone's time zone.
String shortDate(dynamic iso) {
  final parsed = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (parsed == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
}

Color priorityColor(String? priority) {
  switch (priority) {
    case 'urgent':
      return Colors.red.shade700;
    case 'high':
      return Colors.orange.shade800;
    case 'medium':
      return Colors.blue.shade700;
    default:
      return Colors.grey.shade600;
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
          Expanded(child: SelectableText(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

/// Loads one record and shows loading / error / content.
class Loader extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});

  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(BuildContext context, Map<String, dynamic> data, VoidCallback reload) builder;

  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> {
  late Future<Map<String, dynamic>> _future = widget.load();

  void _reload() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorView(error: snapshot.error!, onRetry: _reload);
        }
        return widget.builder(context, snapshot.data!, _reload);
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorText(context, error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(S.of(context).t('retry'))),
          ],
        ),
      ),
    );
  }
}

/// A paginated, pull-to-refresh list backed by one API endpoint
/// that answers with { data: [...], meta: { current_page, last_page } }.
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.path,
    required this.itemBuilder,
    this.query = const {},
    this.header,
  });

  final String path;
  final Map<String, String> query;
  final Widget? header;
  final Widget Function(BuildContext context, Map<String, dynamic> item, VoidCallback refresh) itemBuilder;

  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  final List<Map<String, dynamic>> _items = [];
  int _page = 0;
  int _lastPage = 1;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(PagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.query.toString() != widget.query.toString()) {
      refresh();
    }
  }

  Future<void> refresh() async {
    _page = 0;
    _lastPage = 1;
    await _loadMore(reset: true);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await api.get(widget.path, {...widget.query, 'page': '${_page + 1}'});
      final rows = (body['data'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(rows);
        _page = (body['meta']?['current_page'] as int?) ?? _page + 1;
        _lastPage = (body['meta']?['last_page'] as int?) ?? _page;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return ErrorView(error: _error!, onRetry: refresh);
    }

    final hasMore = _page < _lastPage;
    final headerCount = widget.header == null ? 0 : 1;

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: headerCount + (_items.isEmpty ? 1 : _items.length + (hasMore ? 1 : 0)),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (headerCount == 1 && index == 0) return widget.header!;
          final i = index - headerCount;

          if (_items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(48),
              child: Center(child: Text(s.t('empty'), style: TextStyle(color: Colors.grey.shade600))),
            );
          }
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : TextButton(onPressed: _loadMore, child: Text(s.t('more'))),
              ),
            );
          }
          return widget.itemBuilder(context, _items[i], refresh);
        },
      ),
    );
  }
}
