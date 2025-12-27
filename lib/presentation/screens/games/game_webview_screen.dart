import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GameWebViewScreen extends StatefulWidget {
  final String title;
  final String url;

  const GameWebViewScreen({super.key, required this.title, required this.url});

  @override
  State<GameWebViewScreen> createState() => _GameWebViewScreenState();
}

class _GameWebViewScreenState extends State<GameWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _loadingProgress = 0;
            });
          },
          onProgress: (int progress) {
            setState(() {
              _loadingProgress = progress / 100;
            });
          },
          onPageFinished: (String url) async {
            // Ẩn UI của browser và các elements không cần thiết
            await _hideBrowserUI();
            setState(() {
              _isLoading = false;
              _loadingProgress = 1.0;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi tải trang: ${error.description}'),
                backgroundColor: Colors.red,
              ),
            );
          },
          onNavigationRequest: (NavigationRequest request) {
            // Cho phép mọi điều hướng trong cùng WebView (game thường load iframe/script)
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  // Ẩn UI của browser bằng JavaScript
  Future<void> _hideBrowserUI() async {
    const hideBrowserUIScript = '''
      (function() {
        // Ẩn các elements thường thấy trong trang + tối ưu vùng hiển thị game
        const style = document.createElement('style');
        style.innerHTML = `
          /* Reset cơ bản */
          html, body {
            margin: 0 !important;
            padding: 0 !important;
            width: 100% !important;
            height: 100% !important;
            overflow: auto !important;
          }

          /* Ẩn header/footer/menu của website (để tập trung vào game) */
          header, nav, footer,
          .site-header, .site-footer, .navbar, .menu, .breadcrumb, .breadcrumbs,
          .cookie, .cookie-banner, .cookie-consent,
          .modal, .popup, .overlay, .subscribe, .newsletter {
            display: none !important;
          }

          /* Ẩn quảng cáo (lọc an toàn, tránh match nhầm 'header/load/...') */
          .adsbygoogle,
          [id^="ad-"], [id^="ad_"], [id^="ads-"], [id^="ads_"],
          [class^="ad-"], [class^="ad_"], [class^="ads-"], [class^="ads_"],
          [class*=" ad-"], [class*=" ad_"], [class*=" ads-"], [class*=" ads_"] {
            display: none !important;
          }

          /* Đảm bảo iframe/canvas game hiển thị đúng kích thước */
          iframe, canvas {
            max-width: 100% !important;
          }
          #game-container, .game-container, .game, #game, .game-frame, .game-iframe {
            width: 100% !important;
            max-width: 100% !important;
          }
          iframe {
            width: 100% !important;
            min-height: 70vh !important;
          }
        `;
        document.head.appendChild(style);

        // Nếu có iframe game, đưa nó lên đầu để dễ thấy
        setTimeout(() => {
          const iframe = document.querySelector('iframe');
          if (iframe && iframe.scrollIntoView) {
            iframe.scrollIntoView({ block: 'start' });
          }
        }, 400);
      })();
    ''';
    await _controller.runJavaScript(hideBrowserUIScript);
  }

  // Request fullscreen trong WebView
  Future<void> _requestFullscreen() async {
    const fullscreenScript = '''
      (function() {
        const element = document.documentElement;
        if (element.requestFullscreen) {
          element.requestFullscreen().catch(() => {});
        } else if (element.webkitRequestFullscreen) {
          element.webkitRequestFullscreen();
        } else if (element.mozRequestFullScreen) {
          element.mozRequestFullScreen();
        } else if (element.msRequestFullscreen) {
          element.msRequestFullscreen();
        }
      })();
    ''';
    await _controller.runJavaScript(fullscreenScript);
  }

  // Exit fullscreen trong WebView
  Future<void> _exitFullscreen() async {
    const exitFullscreenScript = '''
      (function() {
        if (document.exitFullscreen) {
          document.exitFullscreen().catch(() => {});
        } else if (document.webkitExitFullscreen) {
          document.webkitExitFullscreen();
        } else if (document.mozCancelFullScreen) {
          document.mozCancelFullScreen();
        } else if (document.msExitFullscreen) {
          document.msExitFullscreen();
        }
      })();
    ''';
    await _controller.runJavaScript(exitFullscreenScript);
  }

  void _toggleFullscreen() async {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });

    // Request hoặc exit fullscreen trong WebView
    if (_isFullscreen) {
      await _requestFullscreen();
    } else {
      await _exitFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(widget.title, style: const TextStyle(fontSize: 16)),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    _controller.reload();
                  },
                  tooltip: 'Tải lại',
                ),
                IconButton(
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                  onPressed: _toggleFullscreen,
                  tooltip: _isFullscreen ? 'Thoát fullscreen' : 'Fullscreen',
                ),
              ],
            ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          // Thanh loading progress ở trên cùng
          if (_isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _loadingProgress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 3,
              ),
            ),
          // Loading overlay với spinner và text
          if (_isLoading)
            Container(
              color: Colors.white.withValues(alpha: 0.9),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Đang tải game...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_loadingProgress * 100).toInt()}%',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          // Nút fullscreen khi ở chế độ fullscreen
          if (_isFullscreen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: _toggleFullscreen,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.fullscreen_exit,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
