import 'dart:async';

import 'adapter.dart';
import 'client.dart';
import 'server_io.dart';
import 'socket.dart';
import 'utils/entity_emitter.dart';
import 'utils/parser.dart';

List<String> events = [
  'connect', // for symmetry with client
  'connection', 'newListener'
];

/// Flags.
List<String> flags = ['json', 'volatile'];

/// a Class that represents a Socket Namespace.
class Namespace extends EventEmitter {
  String name;
  ServerIO server;
  List<Socket> sockets = [];
  Map<String, Socket> connected = {};
  List<Function> fns = [];
  int ids = 0;
  List<String> rooms = [];
  Map flags = {};
  late Adapter adapter;

  /// Namespace constructor.

  Namespace(this.server, this.name) {
    initAdapter();
  }

  /// Initializes the `Adapter` for this nsp.
  /// Run upon changing adapter by `Server#adapter`
  /// in addition to the constructor.
  void initAdapter() {
    adapter = Adapter.newInstance(server.adapter, this);
  }

  /// Sets up namespace middleware.

  Namespace use(fn) {
    fns.add(fn);
    return this;
  }

  /// Executes the middleware for an incoming client.
  void run(socket, Function fn) {
    var fns = this.fns.sublist(0);
    if (fns.isEmpty) {
      fn(null);
      return;
    }

    run0(0, fns, socket, fn);
  }

  static Object run0(
      int index, List<Function> fns, Socket socket, Function fn) {
    return fns[index](socket, (err) {
      // upon error, short-circuit
      if (err) return fn(err);

      // if no middleware left, summon callback
      if (fns.length <= index + 1) return fn(null);

      // go on to next
      return run0(index + 1, fns, socket, fn);
    });
  }

  /// Targets a room when emitting.
  Namespace to(String name) {
    rooms = rooms.isNotEmpty == true ? rooms : [];
    if (!rooms.contains(name)) rooms.add(name);
    return this;
  }

  /// Adds a new client.
  Socket add(Client client, query, Function? fn) {
    var socket = Socket(this, client, query);
    var self = this;

    run(socket, (err) {
      // don't use Timer.run() here

      scheduleMicrotask(() {
        if ('open' == client.conn.readyState) {
          if (err != null) return socket.error(err.data || err.message);

          self.sockets.add(socket);

          socket.onconnect();
          if (fn != null) fn(socket);

          // fire user-set events
          self.emit('connect', socket);
          self.emit('connection', socket);
        }
      });
    });
    return socket;
  }

  /// Removes a client. Called by each `Socket`.
  void remove(socket) {
    if (sockets.contains(socket)) {
      sockets.remove(socket);
    }
  }

  /// Emits to all clients.

  @override
  void emit(String event, [dynamic argument]) {
    if (events.contains(event)) {
      super.emit(event, argument);
    } else {
      List data = argument == null ? [event] : [event, argument];
      final packet = {'type': eventValue, 'data': data};
      adapter.broadcast(packet, {'rooms': rooms, 'flags': flags});
      rooms = [];
      flags = {};
    }
  }

  /// Sends a `message` event to all clients.
  Namespace send([args]) {
    return write(args);
  }

  Namespace write([args]) {
    emit('message', args);
    return this;
  }

  /// Gets a list of clients.
  Namespace clients(Function([dynamic _]) fn) {
    adapter.clients(rooms, fn);
    rooms = [];
    return this;
  }

  /// Sets the compress flag.
  Namespace compress(compress) {
    flags = flags.isEmpty ? flags : {};
    flags['compress'] = compress;
    return this;
  }
}
