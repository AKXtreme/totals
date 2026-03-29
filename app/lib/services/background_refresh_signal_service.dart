import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

class BackgroundRefreshSignalService {
  BackgroundRefreshSignalService._();

  static final BackgroundRefreshSignalService instance =
      BackgroundRefreshSignalService._();

  static const String _portName = 'totals.background_refresh_signal';

  final StreamController<void> _controller =
      StreamController<void>.broadcast();

  ReceivePort? _receivePort;
  bool _isListening = false;

  Stream<void> get stream => _controller.stream;

  void ensureListening() {
    if (_isListening) return;

    final receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(receivePort.sendPort, _portName);

    receivePort.listen((_) {
      if (_controller.isClosed) return;
      _controller.add(null);
    });

    _receivePort = receivePort;
    _isListening = true;
  }

  static void notifyDataChanged() {
    final sendPort = IsolateNameServer.lookupPortByName(_portName);
    sendPort?.send(true);
  }

  void dispose() {
    _receivePort?.close();
    _receivePort = null;
    _isListening = false;
    IsolateNameServer.removePortNameMapping(_portName);
  }
}
