import 'dart:async';
import 'dart:io';

import 'client.dart';
import 'engine/engine.dart';
import 'namespace.dart';

import 'utils/parser.dart';

Map oldSettings = {
  'transports': 'transports',
  'heartbeat timeout': 'pingTimeout',
  'heartbeat interval': 'pingInterval',
  'destroy buffer size': 'maxHttpBufferSize'
};

class ServerIO {
  Map<String, Namespace> nsps = {};
  late Namespace sockets;
  dynamic _origins;
  bool? _serveClient;
  String? _path;
  String _adapter = 'default';
  HttpServer? httpServer;
  Engine? engine;
  Encoder encoder = Encoder();
  Future<bool>? _ready;

  /// Server is ready
  ///
  /// @return a Future that resolves to true whenever the server is ready
  Future<bool> get ready => _ready ?? Future.value(false);

  /// Server's port
  ///
  /// @return the port number where the server is listening
  int? get port {
    if (httpServer == null) {
      return null;
    }
    return httpServer!.port;
  }

  ServerIO({Map? options}) {
    options ??= {};
    path(options.containsKey('path') ? options['path'] : '/socket.io');
    serveClient(false != options['serveClient']);
    adapter = options.containsKey('adapter') ? options['adapter'] : 'default';
    origins(options.containsKey('origins') ? options['origins'] : '*:*');
    sockets = of('/');
    _ready = Future.value(true);
  }
  void checkRequest(HttpRequest req, [Function? fn]) {
    var origin = req.headers.value('origin') ?? req.headers.value('referer');
    if (origin == null || origin.isEmpty) {
      origin = '*';
    }

    if (origin.isNotEmpty && _origins is Function) {
      _origins(origin, fn);
      return;
    }

    if (_origins.contains('*:*')) {
      fn!(null, true);
      return;
    }

    if (origin.isNotEmpty) {
      try {
        var parts = Uri.parse(origin);
        var port = parts.port;
        var ok = _origins.indexOf(parts.host + ':' + port.toString()) >= 0 ||
            _origins.indexOf(parts.host + ':*') >= 0 ||
            _origins.indexOf('*:' + port.toString()) >= 0;

        fn!(null, ok);
        return;
      } catch (ex) {
        //
      }
    }

    fn!(null, false);
  }

  /// Sets/gets whether client code is being served.

  dynamic serveClient([bool? v]) {
    if (v == null) {
      return _serveClient;
    }

    _serveClient = v;
    return this;
  }

  /// Backwards compatiblity.

  ServerIO set(String key, [val]) {
    if ('authorization' == key && val != null) {
      use((socket, next) {
        val(socket.request, (err, authorized) {
          if (err) {
            return next(Exception(err));
          }

          if (!authorized) {
            return next(Exception('Not authorized'));
          }

          next();
        });
      });
    } else if ('origins' == key && val != null) {
      origins(val);
    } else if ('resource' == key) {
      path(val);
    } else if (oldSettings[key] && engine![oldSettings[key]]) {
      engine![oldSettings[key]] = val;
    } else {}

    return this;
  }

  /// Sets the client serving path.
  dynamic path([String? v]) {
    if (v == null || v.isEmpty) return _path;
    _path = v.replaceFirst(RegExp(r'/\/$/'), '');
    return this;
  }

  String get adapter => _adapter;

  set adapter(String v) {
    _adapter = v;
    if (nsps.isNotEmpty) {
      nsps.forEach((String i, Namespace nsp) {
        nsp.initAdapter();
      });
    }
  }

  /// Sets the allowed origins for requests.
  dynamic origins([String? v]) {
    if (v == null || v.isEmpty) return _origins;

    _origins = v;
    return this;
  }

  /// Attaches socket.io to a  port.
  Future<void> listen(dynamic host, int port, [Map? opts]) async {
    await _attach(host, port, opts);
  }

  /// Attaches socket.io to a  server.
  Future<void> listenToHttpServer(
      StreamController<HttpRequest> httpServerStream,
      [Map? opts]) async {
    await _attachToHttpServer(httpServerStream, opts);
  }

  Future<ServerIO> _attachToHttpServer(
      StreamController<HttpRequest> httpServerStream,
      [Map? opts]) async {
    opts ??= {};
    if (!opts.containsKey('path')) {
      opts['path'] = path();
    }
    opts['allowRequest'] = checkRequest;

    var completer = Completer();
    var connectPacket = {'type': connectValue, 'nsp': '/'};
    encoder.encode(connectPacket, (encodedPacket) {
      opts!['initialPacket'] = encodedPacket;
      engine = Engine.attachToHttpServer(httpServerStream, opts);

      bind(engine!);

      completer.complete();
    });
    await completer.future;
    return this;
  }

  Future<ServerIO> _attach(dynamic host, int port, [Map? opts]) async {
    opts ??= {};
    if (!opts.containsKey('path')) {
      opts['path'] = path();
    }
    opts['allowRequest'] = checkRequest;
    var server = await HttpServer.bind(host, port);
    var completer = Completer();
    var connectPacket = {'type': connectValue, 'nsp': '/'};
    encoder.encode(connectPacket, (encodedPacket) {
      opts!['initialPacket'] = encodedPacket;
      engine = Engine.attach(server, opts);
      httpServer = server;
      bind(engine!);

      completer.complete();
    });
    await completer.future;
    return this;
  }

  ServerIO bind(Engine engine) {
    this.engine = engine;
    this.engine!.on('connection', onconnection);
    return this;
  }

  ServerIO onconnection(conn) {
    var client = Client(this, conn);
    client.connect('/');
    return this;
  }

  Namespace of(name, [fn]) {
    if (name.toString()[0] != '/') {
      name = '/' + name;
    }

    if (!nsps.containsKey(name)) {
      var nsp = Namespace(this, name);
      nsps[name] = nsp;
    }
    if (fn != null) nsps[name]!.on('connect', fn);
    return nsps[name]!;
  }

  /// Closes server connection
  Future<void> close() async {
    nsps['/']!.sockets.toList(growable: false).forEach((socket) {
      socket.onclose();
    });

    engine?.close();

    if (httpServer != null) {
      await httpServer!.close();
    }

    _ready = null;
  }

  // redirect to sockets method
  Namespace to(_) => sockets.to(_);
  Namespace use(_) => sockets.use(_);
  void send(_) => sockets.send(_);
  Namespace write(_) => sockets.write(_);
  Namespace clients(_) => sockets.clients(_);
  Namespace compress(_) => sockets.compress(_);

  // emitter
  void emit(event, data) => sockets.emit(event, data);
  void on(event, handler) => sockets.on(event, handler);
  void once(event, handler) => sockets.once(event, handler);
  void off(event, handler) => sockets.off(event, handler);
}
