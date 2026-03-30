import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'server_service.dart';
import 'network_utils.dart';

class ServerTestScreen extends StatefulWidget {
  const ServerTestScreen({super.key});

  @override
  State<ServerTestScreen> createState() => _ServerTestScreenState();
}

class _ServerTestScreenState extends State<ServerTestScreen> {
  final ServerService _serverService = ServerService();
  bool _isLoading = false;
  String? _errorMessage;
  String? _networkIp;
  List<NetworkInterfaceInfo> _interfaces = [];

  @override
  void initState() {
    super.initState();
    _loadNetworkInfo();
  }

  Future<void> _loadNetworkInfo() async {
    final ip = await NetworkUtils.getLocalIpAddress();
    final interfaces = await NetworkUtils.getAllInterfaces();
    if (mounted) {
      setState(() {
        _networkIp = ip;
        _interfaces = interfaces;
      });
    }
  }

  @override
  void dispose() {
    _serverService.stopServer();
    _serverService.dispose();
    super.dispose();
  }

  Future<void> _toggleServer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_serverService.isRunning) {
        await _serverService.stopServer();
      } else {
        await _serverService.startServer();
      }
      // Refresh network info after server starts
      await _loadNetworkInfo();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String get _displayUrl {
    if (_serverService.isRunning) {
      // Use serverUrl which contains the network IP
      return _serverService.serverUrl ??
          'http://$_networkIp:${_serverService.port}';
    }
    return 'Server not running';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Test'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(
                      _serverService.isRunning
                          ? Icons.check_circle
                          : Icons.cancel,
                      color:
                          _serverService.isRunning ? Colors.green : Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _serverService.isRunning
                          ? 'Server Running'
                          : 'Server Stopped',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (_serverService.isRunning) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text(
                        'Network URL (use this on other devices):',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: SelectableText(
                          _displayUrl,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          final url = _displayUrl;
                          if (url.isNotEmpty && url != 'Server not running') {
                            Clipboard.setData(ClipboardData(text: url));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied: $url'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy URL'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Network Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.wifi, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Network Information',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: _loadNetworkInfo,
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Your IP Address:',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _networkIp ?? 'Detecting...',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_interfaces.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Available Interfaces (Wi-Fi shown first):',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      ...(_interfaces.map((iface) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: iface.isWifi
                                        ? Colors.blue
                                        : Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${iface.name}: ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: iface.isWifi
                                        ? Colors.blue.shade700
                                        : null,
                                  ),
                                ),
                                Text(
                                  iface.address,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: iface.isWifi
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: iface.isWifi
                                        ? Colors.blue.shade700
                                        : null,
                                  ),
                                ),
                                if (iface.isWifi) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Wi-Fi',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ))),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Error Message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),

            // Control Button
            FilledButton.icon(
              onPressed: _isLoading ? null : _toggleServer,
              style: FilledButton.styleFrom(
                backgroundColor:
                    _serverService.isRunning ? Colors.red : Colors.green,
                padding: const EdgeInsets.all(16),
              ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_serverService.isRunning
                      ? Icons.stop_circle
                      : Icons.play_circle),
              label: Text(
                _serverService.isRunning ? 'Stop Server' : 'Start Server',
                style: const TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 24),

            // Instructions Card
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Instructions',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.amber.shade900,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '1. Make sure your phone is connected to Wi-Fi\n'
                      '2. Start the server using the button above\n'
                      '3. Copy the Network URL (starts with 192.x.x.x)\n'
                      '4. Open a browser on another device connected to the same Wi-Fi\n'
                      '5. Paste the URL to access the web dashboard',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
