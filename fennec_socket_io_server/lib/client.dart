import 'engine/socket.dart';
import 'server_io.dart';

import 'utils/parser.dart';

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
  /// @param {Server} server instance
  /// @param {Socket} connection
  /// @api private
  Client(this.server, this.conn)
      : id = conn.id,
        request = conn.connect.request {
    setup();
  }

  /// Sets up event listeners.
  ///
  /// @api private
  void setup() {
    decoder.on('decoded', ondecoded);
    conn.on('data', ondata);
    conn.on('error', (data) {});
    conn.on('close', onclose);
  }

  /// Connects a client to a namespace.
  ///
  /// @param {String} namespace name
  /// @api private
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
  ///
  /// @api private
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
  ///
  /// @api private
  void remove(socket) {
    var i = sockets.indexOf(socket);
    if (i >= 0) {
      var nsp = sockets[i].nsp.name;
      sockets.removeAt(i);
      nsps.remove(nsp);
    } else {}
  }

  /// Closes the underlying connection.
  ///
  /// @api private
  void close() {
    if ('open' == conn.readyState) {
      conn.close();
      onclose('forced server close');
    }
  }

  /// Writes a packet to the transport.
  ///
  /// @param {Object} packet object
  /// @param {Object} options
  /// @api private
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
    } else {}
  }

  /// Called with incoming transport data.
  ///
  /// @api private
  void ondata(data) {
    // try/catch is needed for protocol violations (GH-1880)
    try {
      decoder.add(data);
    } catch (e, _) {
      //  onerror(e);
    }
  }

  /// Called when parser fully decodes a packet.
  ///
  /// @api private
  void ondecoded(packet) {
    if (connect == packet['type']) {
      final nsp = packet['nsp'];
      final uri = Uri.parse(nsp);
      connect(uri.path, uri.queryParameters);
    } else {
      var socket = nsps[packet['nsp']];
      if (socket != null) {
        socket.onpacket(packet);
      } else {}
    }
  }

  /// Handles an error.
  ///
  /// @param {Objcet} error object
  /// @api private
  void onerror(err) {
    for (var socket in sockets) {
      socket.onerror(err);
    }
    onclose('client error');
  }

  /// Called upon transport close.
  ///
  /// @param {String} reason
  /// @api private
  void onclose(reason) {
    destroy();

    // `nsps` and `sockets` are cleaned up seamlessly
    if (sockets.isNotEmpty) {
      for (var socket in List.from(sockets)) {
        socket.onclose(reason);
      }
      sockets.clear();
    }
    decoder.destroy(); // clean up decoder
  }

  /// Cleans up event listeners.
  ///
  /// @api private
  void destroy() {
    conn.off('data', ondata);
    conn.off('error', onerror);
    conn.off('close', onclose);
    decoder.off('decoded', ondecoded);
  }
}
