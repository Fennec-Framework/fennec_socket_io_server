import 'dart:async';
import 'dart:io';

import '../utils/entity_emitter.dart';
import 'server.dart';

class Engine extends EventEmitter {
  static Engine attach(server, [Map? options]) {
    var engine = Server(options);
    engine.attachTo(server, options);
    return engine;
  }

  static Engine attachToHttpServer(
      StreamController<HttpRequest> httpServerStream,
      [Map? options]) {
    var engine = Server(options);
    engine.attachToHttpServer(httpServerStream, options);
    return engine;
  }

  dynamic operator [](Object key) {}

  void operator []=(String key, dynamic value) {}

  void close() {}
}
