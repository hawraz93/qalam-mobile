import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

/// Shows a website page inside the app, already signed in as the current user.
/// Used for the teacher portfolio (profile, education, teaching, research, biography)
/// and the account page, so they work exactly as on the website.
class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key, required this.path, required this.title});

  final String path;
  final String title;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  WebViewController? _controller;
  Object? _error;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _controller = null;
    });

    try {
      // One-time link: the website signs this web view in, then shows the page
      final body = await api.post('/web-login', {'path': widget.path});

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
        ));

      // Android web views ignore <input type="file"> unless the app supplies the picker
      // (profile photo, research files). iOS handles it by itself.
      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        await platform.setOnShowFileSelector((params) async {
          final result = await FilePicker.platform.pickFiles(
            allowMultiple: params.mode == FileSelectorMode.openMultiple,
          );
          if (result == null) return [];
          return [
            for (final file in result.files)
              if (file.path != null) Uri.file(file.path!).toString(),
          ];
        });
      }

      await controller.loadRequest(Uri.parse(body['url'] as String));
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Back goes one page back inside the website first, then leaves the screen
        if (controller != null && await controller.canGoBack()) {
          await controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          actions: [
            IconButton(
              tooltip: S.of(context).t('retry'),
              icon: const Icon(Icons.refresh),
              onPressed: controller == null ? _open : controller.reload,
            ),
          ],
          bottom: _progress > 0 && _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress / 100),
                )
              : null,
        ),
        body: _error != null
            ? ErrorView(error: _error!, onRetry: _open)
            : controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: controller),
      ),
    );
  }
}
