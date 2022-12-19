import 'engine/socket.dart';
import 'server_io.dart';

import 'utils/parser.dart';

/// A Class that represents a Socket Client.
class Client {
  ServerIO server;
  Socket conn;
  dynamic id;
  dynamic request;
  Encoder encoder = Encoder();
  Decoder decoder = Decoder();
  List sockets = [];
  Map nsps = {};
  List<String> connectBuffer = [];

  /// Client constructor.
  ///
  /// [server] server instance
  /// [Socket] connection

  Client(this.server, this.conn)
      : id = conn.id,
        request = conn.connect.request {
    setup();
  }

  /// Sets up event listeners.
  ///
  void setup() {
    decoder.on('decoded', ondecoded);
    conn.on('data', ondata);
    conn.on('error', (data) {});
    conn.on('close', onClose);
  }

  /// Connects a client to a namespace.
  ///
  /// [name] namespace name
  void connect(String name, [query]) {
    if (!server.nsps.containsKey(name)) {
      packet(<dynamic, dynamic>{
        'type': errorValue,
        'nsp': name,
        'data': 'Invalid namespace'
      });
      return;
    }

    var nsp = server.of(name);
    if ('/' != name && !nsps.containsKey('/')) {
      connectBuffer.add(name);
      return;
    }

    var self = this;
    nsp.add(this, query, (socket) {
      self.sockets.add(socket);
      self.nsps[nsp.name] = socket;

      if ('/' == nsp.name && self.connectBuffer.isNotEmpty) {
        self.connectBuffer.forEach(self.connect);
        self.connectBuffer = [];
      }
    });
  }

  /// Disconnects from all namespaces and closes transport.
  void disconnect() {
    // we don't use a for loop because the length of
    // `sockets` changes upon each iteration
    sockets.toList().forEach((socket) {
      socket.disconnect();
    });
    sockets.clear();

    close();
  }

  /// Removes a socket. Called by each `Socket`.
  void remove(socket) {
    var i = sockets.indexOf(socket);
    if (i >= 0) {
      var nsp = sockets[i].nsp.name;
      sockets.removeAt(i);
      nsps.remove(nsp);
    } else {}
  }

  /// Closes the underlying connection.
  void close() {
    if ('open' == conn.readyState) {
      conn.close();
      onClose('forced server close');
    }
  }

  /// Writes a packet to the transport.
  /// [packet] packet object
  /// [opts] options
  void packet(packet, [Map? opts]) {
    var self = this;
    opts ??= {};
    // this writes to the actual connection
    void writeToEngine(encodedPackets) {
      if (opts!['volatile'] != null && self.conn.transport.writable != true) {
        return;
      }
      for (var i = 0; i < encodedPackets.length; i++) {
        self.conn.write(encodedPackets[i], {'compress': opts['compress']});
      }
    }

    if ('open' == conn.readyState) {
      if (opts['preEncoded'] != true) {
        // not broadcasting, need to encode
        encoder.encode(packet, (encodedPackets) {
          // encode, then write results to engine
          writeToEngine(encodedPackets);
        });
      } else {
        // a broadcast pre-encodes a packet
        writeToEngine(packet);
      }
    }
  }

  /// Called with incoming transport data.
  void ondata(data) {
    // try/catch is needed for protocol violations (GH-1880)
    try {
      decoder.add(data);
    } catch (e, _) {
      print(e);
    }
  }

  /// Called when parser fully decodes a packet.
  void ondecoded(packet) {
    if (connect == packet['type']) {
      final nsp = packet['nsp'];
      final uri = Uri.parse(nsp);
      connect(uri.path, uri.queryParameters);
    } else {
      var socket = nsps[packet['nsp']];
      if (socket != null) {
        socket.onPacket(packet);
      } else {}
    }
  }

  /// Handles an error.
  /// [err] error object

  void onError(err) {
    for (var socket in sockets) {
      socket.onError(err);
    }
    onClose('client error');
  }

  /// Called upon transport close.
  /// [reason] reason

  void onClose(reason) {
    destroy();

    // `nsps` and `sockets` are cleaned up seamlessly
    if (sockets.isNotEmpty) {
      for (var socket in List.from(sockets)) {
        socket.onClose(reason);
      }
      sockets.clear();
    }
    decoder.destroy(); // clean up decoder
  }

  /// Cleans up event listeners.
  void destroy() {
    conn.off('data', ondata);
    conn.off('error', onError);
    conn.off('close', onClose);
    decoder.off('decoded', ondecoded);
  }
}
