import 'dart:async';
import 'dart:io';

///[SocketConnect]
class SocketConnect {
  WebSocket? _socket;
  Completer? _done;
  bool? _completed;
  HttpRequest request;

  SocketConnect(this.request);

  SocketConnect.fromWebSocket(this.request, WebSocket socket) {
    _socket = socket;
  }

  bool isUpgradeRequest() => _socket != null;

  WebSocket? get websocket => _socket;

  Map<String, dynamic> dataset = {};

  Future get done {
    if (_completed == true) {
      return Future.value('done');
    }
    if (_socket != null) {
      return _socket!.done;
    } else {
      _done = Completer();
      return _done!.future;
    }
  }

  /// Closes the current connection.
  void close() {
    if (_done != null) {
      _done!.complete('done');
    } else if (_socket != null) {
      _socket!.close();
    } else {
      _completed = true;
    }
  }
}
