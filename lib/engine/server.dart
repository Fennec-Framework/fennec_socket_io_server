import 'dart:async';
import 'dart:convert';
import 'dart:io' hide Socket;

import 'engine.dart';
import 'socket.dart';
import 'socket_connect.dart';
import 'transports.dart';
import 'package:uuid/uuid.dart';

class ServerErrors {
  static const int unknownTransport = 0;
  static const int unknownSid = 1;
  static const int badHandshakeMethod = 2;
  static const int badRequest = 3;
  static const int forbidden = 4;
}

const Map<int, String> serverErrorMessages = {
  0: 'Transport unknown',
  1: 'Session ID unknown',
  2: 'Bad handshake method',
  3: 'Bad request',
  4: 'Forbidden'
};

class Server extends Engine {
  Map clients = {};
  int clientsCount = 0;
  late int pingTimeout;
  late int pingInterval;
  late int upgradeTimeout;
  late double maxHttpBufferSize;
  List<String> transports = ['polling', 'websocket'];
  late bool allowUpgrades;
  Function? allowRequest;
  late dynamic cookie;
  late dynamic cookiePath;
  late bool cookieHttpOnly;
  late Map perMessageDeflate;
  late Map httpCompression;
  dynamic initialPacket;
  final Uuid _uuid = Uuid();

  Server([Map? opts]) {
    opts = opts ?? {};

    pingTimeout = opts['pingTimeout'] ?? 60000;
    pingInterval = opts['pingInterval'] ?? 25000;
    upgradeTimeout = opts['upgradeTimeout'] ?? 10000;
    maxHttpBufferSize = opts['maxHttpBufferSize'] ?? 10E7;
    allowUpgrades = false != opts['allowUpgrades'];
    allowRequest = opts['allowRequest'];
    cookie = opts['cookie'] == false
        ? false
        : opts['cookie'] ??
            'io'; //false != opts.cookie ? (opts.cookie || 'io') : false;
    cookiePath = opts['cookiePath'] == false
        ? false
        : opts['cookiePath'] ??
            '/'; //false != opts.cookiePath ? (opts.cookiePath || '/') : false;
    cookieHttpOnly = opts['cookieHttpOnly'] != false;

    if (!opts.containsKey('perMessageDeflate') ||
        opts['perMessageDeflate'] == true) {
      perMessageDeflate =
          opts['perMessageDeflate'] is Map ? opts['perMessageDeflate'] : {};
      if (!perMessageDeflate.containsKey('threshold')) {
        perMessageDeflate['threshold'] = 1024;
      }
    }
    httpCompression = opts['httpCompression'] ?? {};
    if (!httpCompression.containsKey('threshold')) {
      httpCompression['threshold'] = 1024;
    }

    initialPacket = opts['initialPacket'];
    _init();
  }

  /// Initialize websocket server
  ///
  /// @api private
  void _init() {
//  if (this.transports.indexOf('websocket') == -1) return;

//  if (this.ws) this.ws.close();
//
//  var wsModule;
//  try {
//    wsModule = require(this.wsEngine);
//  } catch (ex) {
//    this.wsEngine = 'ws';
//    // keep require('ws') as separate expression for packers (browserify, etc)
//    wsModule = require('ws');
//  }
//  this.ws = new wsModule.Server({
//    noServer: true,
//    clientTracking: false,
//    perMessageDeflate: this.perMessageDeflate,
//    maxPayload: this.maxHttpBufferSize
//  });
  }

  /// Returns a list of available transports for upgrade given a certain transport.
  ///
  /// @return {Array}
  /// @api public
  List<String> upgrades(String transport) {
    if (!allowUpgrades) return List.empty();
    return Transports.upgradesTo(transport);
  }

  /// Verifies a request.
  ///
  /// @param {http.IncomingMessage}
  /// @return {Boolean} whether the request is valid
  /// @api private
  void verify(SocketConnect connect, bool upgrade, fn) {
    // transport check
    var req = connect.request;
    var transport = req.uri.queryParameters['transport'];
    if (!transports.contains(transport)) {
      fn(ServerErrors.unknownTransport, false);
      return;
    }
    var sid = req.uri.queryParameters['sid'];
    if (sid != null) {
      if (!clients.containsKey(sid)) {
        fn(ServerErrors.unknownSid, false);
        return;
      }
      if (!upgrade && clients[sid].transport.name != transport) {
        fn(ServerErrors.badRequest, false);
        return;
      }
    } else {
      if ('GET' != req.method) {
        fn(ServerErrors.badHandshakeMethod, false);
        return;
      }
      if (allowRequest == null) {
        fn(null, true);
        return;
      }
      allowRequest!(req, fn);
      return;
    }

    fn(null, true);
    return;
  }

  @override
  void close() {
    for (var key in clients.keys.toList(growable: false)) {
      if (clients[key] != null) {
        clients[key].close(true);
      }
    }
  }

  void handleRequest(SocketConnect connect) {
    var req = connect.request;

    var self = this;
    verify(connect, false, (err, success) {
      if (!success) {
        sendErrorMessage(req, err);
        return;
      }
      if (req.uri.queryParameters['sid'] != null) {
        self.clients[req.uri.queryParameters['sid']].transport
            .onRequest(connect);
      } else {
        self.handshake(req.uri.queryParameters['transport'] as String, connect);
      }
    });
  }

  static void sendErrorMessage(HttpRequest req, code) {
    var res = req.response;
    var isForbidden = !serverErrorMessages.containsKey(code);
    if (isForbidden) {
      res.statusCode = HttpStatus.forbidden;
      res.headers.contentType = ContentType.json;
      res.write(json.encode({
        'code': ServerErrors.forbidden,
        'message': code ?? serverErrorMessages[ServerErrors.forbidden]
      }));
      return;
    }
    if (req.headers.value('origin') != null) {
      res.headers.add('Access-Control-Allow-Credentials', 'true');
      res.headers
          .add('Access-Control-Allow-Origin', req.headers.value('origin')!);
    } else {
      res.headers.add('Access-Control-Allow-Origin', '*');
    }
    res.statusCode = HttpStatus.badRequest;
    res.write(
        json.encode({'code': code, 'message': serverErrorMessages[code]}));
  }

  /// generate a socket id.
  /// Overwrite this method to generate your custom socket id
  ///
  /// @param {Object} request object
  /// @api public
  String generateId(SocketConnect connect) {
    return _uuid.v1().replaceAll('-', '');
  }

  /// Handshakes a new client.
  ///
  /// @param {String} transport name
  /// @param {Object} request object
  /// @api private
  void handshake(String transportName, SocketConnect connect) {
    var id = generateId(connect);

    Transport transport;
    var req = connect.request;
    try {
      transport = Transports.newInstance(transportName, connect);
      if ('polling' == transportName) {
        transport.maxHttpBufferSize = maxHttpBufferSize;
        transport.httpCompression = httpCompression;
      } else if ('websocket' == transportName) {
        transport.perMessageDeflate = perMessageDeflate;
      }

      if (req.uri.hasQuery && req.uri.queryParameters.containsKey('b64')) {
        transport.supportsBinary = false;
      } else {
        transport.supportsBinary = true;
      }
    } catch (e) {
      sendErrorMessage(req, ServerErrors.badRequest);
      return;
    }
    var socket = Socket(id, this, transport, connect);

    if (cookie?.isNotEmpty == true) {
      transport.on('headers', (headers) {
        headers['Set-Cookie'] = '$cookie=${Uri.encodeComponent(id)}' +
            (cookiePath?.isNotEmpty == true ? '; Path=$cookiePath' : '') +
            (cookiePath?.isNotEmpty == true && cookieHttpOnly == true
                ? '; HttpOnly'
                : '');
      });
    }

    transport.onRequest(connect);

    clients[id] = socket;
    clientsCount++;

    socket.once('close', (_) {
      clients.remove(id);
      clientsCount--;
    });

    emit('connection', socket);
  }

  /// Handles an Engine.IO HTTP Upgrade.
  ///
  /// @api public
  void handleUpgrade(SocketConnect connect) {
//  this.prepare(req);

    verify(connect, true, (err, success) {
      if (!success) {
        abortConnection(connect, err);
        return;
      }

//  var head = new Buffer(upgradeHead.length);
//  upgradeHead.copy(head);
//  upgradeHead = null;

      // delegate to ws
//  self.ws.handleUpgrade(req, socket, head, function (conn) {
      onWebSocket(connect);

//  });
    });
  }

  /// Called upon a ws.io connection.
  ///
  /// @param {ws.Socket} websocket
  /// @api private
  void onWebSocket(SocketConnect connect) {
//    socket.listen((_) {},
//        onError: () => _logger.fine('websocket error before upgrade'));

//  if (!transports[req._query.transport].handlesUpgrades) {
//    _logger.fine('transport doesnt handle upgraded requests');
//    socket.close();
//    return;
//  }
    if (connect.request.connectionInfo == null) {
      return;
    }
    // get client id
    var id = connect.request.uri.queryParameters['sid'];

    // keep a reference to the ws.Socket
//  req.websocket = socket;

    if (id != null) {
      var client = clients[id];

      if (client == null) {
        connect.websocket?.close();
      } else if (client.upgrading == true) {
        connect.websocket?.close();
      } else if (client.upgraded == true) {
        connect.websocket?.close();
      } else {
        var req = connect.request;
        var transport = Transports.newInstance(
            req.uri.queryParameters['transport'] as String, connect);
        // ignore: unrelated_type_equality_checks
        if (req.uri.queryParameters['b64'] == true) {
          transport.supportsBinary = false;
        } else {
          transport.supportsBinary = true;
        }
        transport.perMessageDeflate = perMessageDeflate;
        client.maybeUpgrade(transport);
      }
    } else {
      handshake(
          connect.request.uri.queryParameters['transport'] as String, connect);
    }
  }

  /// Captures upgrade requests for a http.Server.
  ///
  /// @param {http.Server} server
  /// @param {Object} options
  /// @api public
  void attachTo(HttpServer server, Map? options) {
    options = options ?? {};

    // cache and clean up listeners
    server.listen((event) async {
      var req = event;

      if (WebSocketTransformer.isUpgradeRequest(req) &&
          transports.contains('websocket')) {
        var socket = await WebSocketTransformer.upgrade(req);

        var socketConnect = SocketConnect.fromWebSocket(req, socket);

        socketConnect.dataset['options'] = options;

        handleUpgrade(socketConnect);

        return socketConnect.done;
      } else {
        var socketConnect = SocketConnect(req);
        socketConnect.dataset['options'] = options;
        handleRequest(socketConnect);
        return socketConnect.done;
      }
    });
  }

  void attachToHttpServer(
      StreamController<HttpRequest> streamController, Map? options) {
    options = options ?? {};
    streamController.stream.listen((event) async {
      var req = event;
      if (WebSocketTransformer.isUpgradeRequest(req) &&
          transports.contains('websocket')) {
        var socket = await WebSocketTransformer.upgrade(req);
        var socketConnect = SocketConnect.fromWebSocket(req, socket);
        socketConnect.dataset['options'] = options;
        handleUpgrade(socketConnect);
        return socketConnect.done;
      } else {
        var socketConnect = SocketConnect(req);
        socketConnect.dataset['options'] = options;
        handleRequest(socketConnect);
        return socketConnect.done;
      }
    });
  }

  static void abortConnection(SocketConnect connect, code) {
    var socket = connect.websocket;
    if (socket?.readyState == HttpStatus.ok) {
      var message = serverErrorMessages.containsKey(code)
          ? serverErrorMessages[code]
          : code;

      var length = utf8.encode(message).length;
      socket!.add('HTTP/1.1 400 Bad Request\r\n'
              'Connection: close\r\n'
              'Content-type: text/html\r\n'
              'Content-Length: $length\r\n'
              '\r\n' +
          message);
    }
    socket?.close();
  }
}
