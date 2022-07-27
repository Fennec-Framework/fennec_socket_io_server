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
  ///
  /// @param {Server} server instance
  /// @param {Socket} name
  /// @api private
  Namespace(this.server, this.name) {
    initAdapter();
  }

  /// Initializes the `Adapter` for this nsp.
  /// Run upon changing adapter by `Server#adapter`
  /// in addition to the constructor.
  ///
  /// @api private
  void initAdapter() {
    adapter = Adapter.newInstance(server.adapter, this);
  }

  /// Sets up namespace middleware.
  ///
  /// @return {Namespace} self
  /// @api public
  Namespace use(fn) {
    fns.add(fn);
    return this;
  }

  /// Executes the middleware for an incoming client.
  ///
  /// @param {Socket} socket that will get added
  /// @param {Function} last fn call in the middleware
  /// @api private
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
  ///
  /// @param {String} name
  /// @return {Namespace} self
  /// @api public
//    in(String name) {
//        to(name);
//    }

  /// Targets a room when emitting.
  ///
  /// @param {String} name
  /// @return {Namespace} self
  /// @api public
  Namespace to(String name) {
    rooms = rooms.isNotEmpty == true ? rooms : [];
    if (!rooms.contains(name)) rooms.add(name);
    return this;
  }

  /// Adds a new client.
  ///
  /// @return {Socket}
  /// @api private
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
        } else {}
      });
    });
    return socket;
  }

  /// Removes a client. Called by each `Socket`.
  ///
  /// @api private
  void remove(socket) {
    if (sockets.contains(socket)) {
      sockets.remove(socket);
    } else {}
  }

  /// Emits to all clients.
  ///
  /// @api public
  @override
  void emit(String event, [dynamic argument]) {
    if (events.contains(event)) {
      super.emit(event, argument);
    } else {
      // @todo check how to handle it with Dart
      // if (hasBin(args)) { parserType = ParserType.binaryEvent; } // binary

      // ignore: omit_local_variable_types
      List data = argument == null ? [event] : [event, argument];

      final packet = {'type': eventValue, 'data': data};

      adapter.broadcast(packet, {'rooms': rooms, 'flags': flags});

      rooms = [];
      flags = {};
    }
  }

  /// Sends a `message` event to all clients.
  ///
  /// @return {Namespace} self
  /// @api public
  Namespace send([args]) {
    return write(args);
  }

  Namespace write([args]) {
    emit('message', args);
    return this;
  }

  /// Gets a list of clients.
  ///
  /// @return {Namespace} self
  /// @api public
  ///

  ///
  // ignore: use_function_type_syntax_for_parameters
  Namespace clients(fn([_])) {
    adapter.clients(rooms, fn);
    rooms = [];
    return this;
  }

  /// Sets the compress flag.
  ///
  /// @param {Boolean} if `true`, compresses the sending data
  /// @return {Namespace} self
  /// @api public
  Namespace compress(compress) {
    flags = flags.isEmpty ? flags : {};
    flags['compress'] = compress;
    return this;
  }
}
