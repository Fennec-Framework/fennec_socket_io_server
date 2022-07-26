import 'dart:async';
import 'dart:html';

class SocketIOConfig {
  dynamic host;
  int port;
  StreamController<HttpRequest>? httpServerStream;
  SocketIOConfig(this.host, this.port);
}
