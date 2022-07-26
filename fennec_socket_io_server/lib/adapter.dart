import 'dart:async';

import 'package:fennec_socket_io_server/socket.dart';

import 'namespace.dart';
import 'utils/entity_emitter.dart';
import 'utils/parser.dart';

abstract class Adapter {
  Map nsps = {};
  Map<String, _Room> rooms = {};
  Map<String, Map> sids = {};

  void add(String id, String room, [dynamic Function([dynamic]) fn]);
  void del(String id, String room, [dynamic Function([dynamic]) fn]);
  void delAll(String id, [dynamic Function([dynamic]) fn]);
  void broadcast(Map packet, [Map opts]);
  void clients([List<String> rooms, dynamic Function([dynamic]) fn]);
  void clientRooms(String id, [dynamic Function(dynamic, [dynamic]) fn]);

  static Adapter newInstance(String key, Namespace nsp) {
    if ('default' == key) {
      return _MemoryStoreAdapter(nsp);
    }
    throw UnimplementedError('not supported other adapter yet.');
  }
}

class _MemoryStoreAdapter extends EventEmitter implements Adapter {
  @override
  Map nsps = {};
  @override
  Map<String, _Room> rooms = {};

  @override
  Map<String, Map> sids = {};
  late Encoder encoder;
  late Namespace nsp;

  _MemoryStoreAdapter(Namespace nsp) {
    nsp = nsp;
    encoder = nsp.server.encoder;
  }

  /// Adds a socket to a room.
  ///
  /// @param {String} socket id
  /// @param {String} room name
  /// @param {Function} callback
  /// @api public
  @override
  void add(String id, String room, [dynamic Function([dynamic])? fn]) {
    sids[id] = sids[id] ?? {};
    sids[id]![room] = true;
    rooms[room] = rooms[room] ?? _Room();
    rooms[room]!.add(id);
    if (fn != null) scheduleMicrotask(() => fn(null));
  }

  /// Removes a socket from a room.
  ///
  /// @param {String} socket id
  /// @param {String} room name
  /// @param {Function} callback
  /// @api public
  @override
  void del(String id, String room, [dynamic Function([dynamic])? fn]) {
    sids[id] = sids[id] ?? {};
    sids[id]!.remove(room);
    if (rooms.containsKey(room)) {
      rooms[room]!.del(id);
      if (rooms[room]!.length == 0) rooms.remove(room);
    }

    if (fn != null) scheduleMicrotask(() => fn(null));
  }

  /// Removes a socket from all rooms it's joined.
  ///
  /// @param {String} socket id
  /// @param {Function} callback
  /// @api public
  @override
  void delAll(String id, [dynamic Function([dynamic])? fn]) {
    var rooms = sids[id];
    if (rooms != null) {
      for (var room in rooms.keys) {
        if (this.rooms.containsKey(room)) {
          this.rooms[room]!.del(id);
          if (this.rooms[room]!.length == 0) this.rooms.remove(room);
        }
      }
    }
    sids.remove(id);

    if (fn != null) scheduleMicrotask(() => fn(null));
  }

  /// Broadcasts a packet.
  ///
  /// Options:
  ///  - `flags` {Object} flags for this packet
  ///  - `except` {Array} sids that should be excluded
  ///  - `rooms` {Array} list of rooms to broadcast to
  ///
  /// @param {Object} packet object
  /// @api public
  @override
  void broadcast(Map packet, [Map? opts]) {
    opts = opts ?? {};
    List rooms = opts['rooms'] ?? [];
    List except = opts['except'] ?? [];
    Map flags = opts['flags'] ?? {};
    var packetOpts = {
      'preEncoded': true,
      'volatile': flags['volatile'],
      'compress': flags['compress']
    };
    var ids = {};
    Socket? socket;

    packet['nsp'] = nsp.name;
    encoder.encode(packet, (encodedPackets) {
      if (rooms.isNotEmpty) {
        for (var i = 0; i < rooms.length; i++) {
          var room = this.rooms[rooms[i]];
          if (room == null) continue;
          var sockets = room.sockets;
          for (var id in sockets.keys) {
            if (sockets.containsKey(id)) {
              if (ids[id] != null || except.contains(id)) continue;
              socket = nsp.connected[id];
              if (socket != null) {
                socket!.packet(encodedPackets, packetOpts);
                ids[id] = true;
              }
            }
          }
        }
      } else {
        for (var id in sids.keys) {
          if (except.contains(id)) continue;
          socket = nsp.connected[id];
          if (socket != null) socket!.packet(encodedPackets, packetOpts);
        }
      }
    });
  }

  /// Gets a list of clients by sid.
  ///
  /// @param {Array} explicit set of rooms to check.
  /// @param {Function} callback
  /// @api public
  @override
  void clients(
      [List<String> rooms = const [], dynamic Function([dynamic])? fn]) {
    var ids = {};
    var sids = [];
    Socket? socket;

    if (rooms.isNotEmpty) {
      for (var i = 0; i < rooms.length; i++) {
        var room = this.rooms[rooms[i]];
        if (room == null) continue;
        var sockets = room.sockets;
        for (var id in sockets.keys) {
          if (sockets.containsKey(id)) {
            if (ids[id] != null) continue;
            socket = nsp.connected[id];
            if (socket != null) {
              sids.add(id);
              ids[id] = true;
            }
          }
        }
      }
    } else {
      for (var id in this.sids.keys) {
        socket = nsp.connected[id];
        if (socket != null) sids.add(id);
      }
    }

    if (fn != null) scheduleMicrotask(() => fn(sids));
  }

  /// Gets the list of rooms a given client has joined.
  ///
  /// @param {String} socket id
  /// @param {Function} callback
  /// @api public
  @override
  void clientRooms(String id, [dynamic Function(dynamic, [dynamic])? fn]) {
    var rooms = sids[id];
    if (fn != null) scheduleMicrotask(() => fn(null, rooms?.keys));
  }
}

/// Room constructor.
///
/// @api private
class _Room {
  Map<String, bool> sockets = {};
  int length = 0;

  /// Adds a socket to a room.
  ///
  /// @param {String} socket id
  /// @api private
  void add(String id) {
    if (!sockets.containsKey(id)) {
      sockets[id] = true;
      length++;
    }
  }

  /// Removes a socket from a room.
  ///
  /// @param {String} socket id
  /// @api private
  void del(String id) {
    if (sockets.containsKey(id)) {
      sockets.remove(id);
      length--;
    }
  }
}
