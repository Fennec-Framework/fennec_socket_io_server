import 'dart:io';

import 'adapter.dart';
import 'client.dart';
import 'namespace.dart';
import 'server_io.dart';
import 'utils/entity_emitter.dart';
import 'utils/parser.dart';

/// all possible socket events
List events = [
  'error',
  'connect',
  'disconnect',
  'newListener',
  'removeListener'
];

/// Flags.

List flags = ['json', 'volatile', 'broadcast'];

const List socketEvents = [
  'error',
  'connect',
  'disconnect',
  'disconnecting',
  'newListener',
  'removeListener'
];

/// [Socket]
class Socket extends EventEmitter {
  Namespace nsp;
  Client client;
  late ServerIO server;
  late Adapter adapter;
  late String id;
  late HttpRequest request;
  dynamic conn;
  Map roomMap = {};
  List roomList = [];
  Map acks = {};
  bool connected = true;
  bool disconnected = false;
  Map? handshake;
  Map<String, bool>? flags;

  Map data = {};

  Socket(this.nsp, this.client, query) {
    server = nsp.server;
    adapter = nsp.adapter;
    id = client.id;
    request = client.request;
    conn = client.conn;
    handshake = buildHandshake(query);
  }

  Map buildHandshake(query) {
    Map buildQuery() {
      var requestQuery = request.uri.queryParameters;
      return query != null
          ? (Map.from(query)..addAll(requestQuery))
          : requestQuery;
    }

    return {
      'headers': request.headers,
      'time': DateTime.now().toString(),
      'address': conn.remoteAddress,
      'xdomain': request.headers.value('origin') != null,
      'issued': DateTime.now().millisecondsSinceEpoch,
      'url': request.uri.path,
      'query': buildQuery()
    };
  }

  Socket get json {
    flags = flags ?? {};
    flags!['json'] = true;
    return this;
  }

  Socket get volatile {
    flags = flags ?? {};
    flags!['volatile'] = true;
    return this;
  }

  Socket get broadcast {
    flags = flags ?? {};
    flags!['broadcast'] = true;
    return this;
  }

  @override
  void emit(String event, [data]) {
    emitWithAck(event, data);
  }

  void emitWithBinary(String event, [data]) {
    emitWithAck(event, data, binary: true);
  }

  void emitWithAck(String event, dynamic data,
      {Function? ack, bool binary = false}) {
    if (socketEvents.contains(event)) {
      super.emit(event, data);
    } else {
      var packet = {};
      var sendData = data == null ? [event] : [event, data];

      var flags = this.flags ?? {};

      if (ack != null) {
        if (roomList.isNotEmpty || flags['broadcast'] == true) {
          throw UnsupportedError(
              'Callbacks are not supported when broadcasting');
        }

        acks['${nsp.ids}'] = ack;
        packet['id'] = '${nsp.ids++}';
      }

      packet['type'] = binary ? binaryEventValue : eventValue;
      packet['data'] = sendData;

      if (roomList.isNotEmpty || flags['broadcast'] == true) {
        adapter.broadcast(packet, {
          'except': [id],
          'rooms': roomList,
          'flags': flags
        });
      } else {
        // dispatch packet
        this.packet(packet,
            {'volatile': flags['volatile'], compress: flags['compress']});
      }
      roomList = [];
      this.flags = null;
    }
  }

  /// Targets a room when broadcasting.
  ///
  ///  [name]
  /// @return [Socket] self

  Socket to(String name) {
    if (!roomList.contains(name)) roomList.add(name);
    return this;
  }

  /// Sends a `message` event.
  ///
  /// @return {Socket} self
  /// @api public
  void send(_) {
    write(_);
  }

  Socket write(List data) {
    emit('message', data);
    return this;
  }

  /// Writes a packet.
  ///
  /// @param {Object} packet object
  /// @param {Object} options
  /// @api private
  void packet(packet, [opts]) {
    if (packet is Map) {
      packet['nsp'] = nsp.name;
    }
    opts = opts ?? {};
    opts['compress'] = false != opts['compress'];
    client.packet(packet, opts);
  }

  /// Joins a room.
  ///
  /// @param {String} room
  /// @param {Function} optional, callback
  /// @return {Socket} self
  /// @api private
  Socket join(room, [fn]) {
    if (roomMap.containsKey(room)) {
      if (fn != null) fn(null);
      return this;
    }
    adapter.add(id, room, ([err]) {
      if (err != null) return fn?.call(err);
//      _logger.info('joined room %s', room);
      roomMap[room] = room;
      if (fn != null) fn(null);
    });
    return this;
  }

  /// Leaves a room.
  ///
  /// @param {String} room
  /// @param {Function} optional, callback
  /// @return {Socket} self
  /// @api private
  Socket leave(room, fn) {
    adapter.del(id, room, ([err]) {
      if (err != null) return fn?.call(err);
      roomMap.remove(room);
      fn?.call(null);
    });
    return this;
  }

  /// Leave all rooms.
  ///
  /// @api private
  void leaveAll() {
    adapter.delAll(id);
    roomMap = {};
  }

  /// Called by `Namespace` upon succesful
  /// middleware execution (ie: authorization).
  ///
  /// @api private
  void onconnect() {
//    debug('socket connected - writing packet');
    nsp.connected[id] = this;
    join(id);
    packet(<dynamic, dynamic>{'type': connectValue});
  }

  /// Called with each packet. Called by `Client`.
  ///
  /// @param {Object} packet
  /// @api private
  void onPacket(packet) {
    switch (packet['type']) {
      case eventValue:
        onEvent(packet);
        break;

      case binaryEventValue:
        onEvent(packet);
        break;

      case ackValue:
        onAck(packet);
        break;

      case binaryAckValue:
        onAck(packet);
        break;

      case disconnectValue:
        onDisconnect();
        break;

      case errorValue:
        emit('error', packet['data']);
    }
  }

  /// Called upon event packet.
  ///
  /// @param {Object} packet object
  /// @api private
  void onEvent(packet) {
    List args = packet['data'] ?? [];
    if (null != packet['id']) {
      args.add(ack(packet['id']));
    }
    // dart doesn't support "String... rest" syntax.
    if (args.length > 2) {
      Function.apply(super.emit, [args.first, args.sublist(1)]);
    } else {
      Function.apply(super.emit, args);
    }
  }

  /// Produces an ack callback to emit with an event.
  ///
  /// @param {Number} packet id
  /// @api private
  Function ack(id) {
    var sent = false;
    return (_) {
      // prevent double callbacks
      if (sent) return;
      var type = ackValue;
      packet(<dynamic, dynamic>{
        'id': id,
        'type': type,
        'data': [_]
      });
      sent = true;
    };
  }

  /// Called upon ack packet.
  ///
  /// @api private
  void onAck(packet) {
    Function ack = acks.remove(packet['id']);
    Function.apply(ack, packet['data']);
  }

  /// Called upon client disconnect packet.
  ///
  /// @api private
  void onDisconnect() {
    onClose('client namespace disconnect');
  }

  /// Handles a client error.
  ///
  /// @api private
  void onError(err) {
    if (hasListeners('error')) {
      emit('error', err);
    }
  }

  /// Called upon closing. Called by `Client`.
  ///
  /// @param {String} reason
  /// @param {Error} optional error object
  /// @api private
  dynamic onClose([reason]) {
    if (!connected) return this;
    emit('disconnecting', reason);
    leaveAll();
    nsp.remove(this);
    client.remove(this);
    connected = false;
    disconnected = true;
    nsp.connected.remove(id);
    emit('disconnect', reason);
  }

  /// Produces an `error` packet.
  ///
  /// @param {Object} error object
  /// @api private
  void error(err) {
    packet(<dynamic, dynamic>{'type': errorValue, 'data': err});
  }

  /// Disconnects this client.
  ///
  /// @param {Boolean} if `true`, closes the underlying connection
  /// @return {Socket} self
  /// @api public
  Socket disconnect([close]) {
    if (!connected) return this;
    if (close == true) {
      client.disconnect();
    } else {
      packet(<dynamic, dynamic>{'type': disconnectValue});
      onClose('server namespace disconnect');
    }
    return this;
  }

  /// Sets the compress flag.
  ///
  /// @param {Boolean} if `true`, compresses the sending data
  /// @return {Socket} self
  /// @api public
  Socket compress(compress) {
    flags = flags ?? {};
    flags!['compress'] = compress;
    return this;
  }
}
