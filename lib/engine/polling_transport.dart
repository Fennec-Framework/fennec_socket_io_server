import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fennec_socket_io_server/engine/transports.dart';

import 'socket_connect.dart';
import 'utils/packet_parser.dart';

class PollingTransport extends Transport {
  @override
  bool get handlesUpgrades => false;

  @override
  bool get supportsFraming => false;

  int closeTimeout = 30 * 1000;
  Function? shouldClose;
  SocketConnect? dataReq;
  PollingTransport(connect) : super(connect) {
    maxHttpBufferSize = null;
    httpCompression = null;
    name = 'polling';
  }

  @override
  void onRequest(SocketConnect connect) {
    var res = connect.request.response;

    if ('GET' == connect.request.method) {
      onPollRequest(connect);
    } else if ('POST' == connect.request.method) {
      onDataRequest(connect);
    } else {
      res.statusCode = 500;
      res.close();
    }
  }

  final Map<SocketConnect, Function> _reqCleanups = {};
  final Map<SocketConnect, Function> _reqCloses = {};

  void onPollRequest(SocketConnect connect) {
    if (this.connect != null) {
      // assert: this.res, '.req and .res should be (un)set together'
      onError('overlap from client');
      this.connect!.request.response.statusCode = 500;
      this.connect!.close();
      return;
    }

    this.connect = connect;

    onClose() {
      onError('poll connection closed prematurely');
    }

    cleanup() {
      _reqCloses.remove(connect);
      this.connect = null;
    }

    _reqCleanups[connect] = cleanup;
    _reqCloses[connect] = onClose;

    writable = true;
    emit('drain');

    // if we're still writable but had a pending close, trigger an empty send
    if (writable == true && shouldClose != null) {
      send([
        {'type': 'noop'}
      ]);
    }
  }

  /// The client sends a request with data.

  void onDataRequest(SocketConnect connect) {
    if (dataReq != null) {
      // assert: this.dataRes, '.dataReq and .dataRes should be (un)set together'
      onError('data request overlap from client');
      connect.request.response.statusCode = 500;
      connect.close();
      return;
    }

    var isBinary = 'application/octet-stream' ==
        connect.request.headers.value('content-type');

    dataReq = connect;

    dynamic chunks = isBinary ? [0] : '';
    var self = this;
    StreamSubscription? subscription;
    cleanup() {
      chunks = isBinary ? [0] : '';
      if (subscription != null) {
        subscription.cancel();
      }
      self.dataReq = null;
    }

    onData(List<int> data) {
      dynamic contentLength;
      if (data is String) {
        chunks += data;
        contentLength = utf8.encode(chunks).length;
      } else {
        if (chunks is String) {
          chunks += String.fromCharCodes(data);
        } else {
          chunks.addAll(String.fromCharCodes(data)
              .split(',')
              .map((s) => int.parse(s))
              .toList());
        }
        contentLength = chunks.length;
      }

      if (contentLength > self.maxHttpBufferSize) {
        chunks = '';
        connect.close();
      }
    }

    onEnd() {
      self.onData(chunks);

      var headers = {'Content-Type': 'text/html', 'Content-Length': 2};

      var res = connect.request.response;

      res.statusCode = 200;

      res.headers.clear();
      // text/html is required instead of text/plain to avoid an
      // unwanted download dialog on certain user-agents (GH-43)
      self.headers(connect, headers).forEach((key, value) {
        res.headers.set(key, value);
      });
      res.write('ok');
      connect.close();
      cleanup();
    }

    subscription = connect.request.listen(onData, onDone: onEnd);
    if (!isBinary) {
      connect.request.headers.contentType =
          ContentType.text; // for encoding utf-8
    }
  }

  /// Processes the incoming data payload.
  @override
  void onData(data) {
    if (messageHandler != null) {
      messageHandler!.handle(this, data);
    } else {
      var self = this;
      callback(packet, [foo, bar]) {
        if ('close' == packet['type']) {
          self.onClose();
          return false;
        }

        self.onPacket(packet);
        return true;
      }

      PacketParser.decodePayload(data, callback: callback);
    }
  }

  /// Overrides onClose.
  @override
  void onClose() {
    if (writable == true) {
      // close pending poll request
      send([
        {'type': 'noop'}
      ]);
    }
    super.onClose();
  }

  /// Writes a packet payload.
  @override
  void send(List packets) {
    writable = false;

    if (shouldClose != null) {
      packets.add({'type': 'close'});
      shouldClose!();
      shouldClose = null;
    }

    var self = this;
    PacketParser.encodePayload(packets, supportsBinary: supportsBinary == true,
        callback: (data) {
      var compress = packets.any((packet) {
        var opt = packet['options'];
        return opt != null && opt['compress'] == true;
      });
      self.write(data, {'compress': compress});
    });
  }

  /// Writes data as response to poll request.
  void write(data, [options]) {
    doWrite(data, options, () {
      var fn = _reqCleanups.remove(connect);
      if (fn != null) fn();
    });
  }

  /// Performs the write.

  void doWrite(data, options, [callback]) {
    var self = this;

    // explicit UTF-8 is required for pages not served under utf
    var isString = data is String;
    var contentType =
        isString ? 'text/plain; charset=UTF-8' : 'application/octet-stream';

    final headers = <String, dynamic>{'Content-Type': contentType};

    respond(data) {
      headers[HttpHeaders.contentLengthHeader] =
          data is String ? utf8.encode(data).length : data.length;
      var res = self.connect!.request.response;

      // If the status code is 101 (aka upgrade), then
      // we assume the WebSocket transport has already
      // sent the response and closed the socket
      if (res.statusCode != 101) {
        res.statusCode = 200;

        res.headers.clear(); // remove all default headers.
        this.headers(connect!, headers).forEach((k, v) {
          res.headers.set(k, v);
        });
        try {
          if (data is String) {
            res.write(data);
            connect!.close();
          } else {
            if (headers.containsKey(HttpHeaders.contentEncodingHeader)) {
              res.add(data);
            } else {
              res.write(String.fromCharCodes(data));
            }
            connect!.close();
          }
        } catch (e) {
          var fn = _reqCloses.remove(connect);
          if (fn != null) fn();
          rethrow;
        }
      }
      callback();
    }

    if (httpCompression == null || options['compress'] != true) {
      respond(data);
      return;
    }

    var len = isString ? utf8.encode(data).length : data.length;
    if (len < httpCompression?['threshold']) {
      respond(data);
      return;
    }

    var encodings =
        connect!.request.headers.value(HttpHeaders.acceptEncodingHeader);
    var hasGzip = encodings!.contains('gzip');
    if (!hasGzip && !encodings.contains('deflate')) {
      respond(data);
      return;
    }
    var encoding = hasGzip ? 'gzip' : 'deflate';
//    this.compress(data, encoding, (err, data) {
//      if (err != null) {
//        self.req.response..statusCode = 500..close();
//        callback(err);
//        return;
//      }

    headers[HttpHeaders.contentEncodingHeader] = encoding;
    respond(hasGzip
        ? gzip.encode(utf8.encode(
            data is List ? String.fromCharCodes(data as List<int>) : data))
        : data);
//    });
  }

  /// Closes the transport.

  @override
  void doClose([dynamic Function()? fn]) {
    var self = this;
    Timer? closeTimeoutTimer;

    if (dataReq != null) {
      dataReq = null;
    }

    onClose() {
      if (closeTimeoutTimer != null) closeTimeoutTimer.cancel();
      if (fn != null) fn();
      self.onClose();
    }

    if (writable == true) {
      send([
        {'type': 'close'}
      ]);
      onClose();
    } else if (discarded) {
      onClose();
    } else {
      shouldClose = onClose;
      closeTimeoutTimer = Timer(Duration(milliseconds: closeTimeout), onClose);
    }
  }

  /// Returns headers for a response.
  Map headers(SocketConnect connect, [Map? headers]) {
    headers = headers ?? {};

    // prevent XSS warnings on IE
    // https://github.com/LearnBoost/socket.io/pull/1333
    var ua = connect.request.headers.value('user-agent');
    if (ua != null && (ua.contains(';MSIE') || ua.contains('Trident/'))) {
      headers['X-XSS-Protection'] = '0';
    }

    emit('headers', headers);
    return headers;
  }
}
