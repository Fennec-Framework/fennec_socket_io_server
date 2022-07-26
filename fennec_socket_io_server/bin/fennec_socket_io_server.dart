import 'dart:async';

import 'package:fennec_socket_io_server/engine/socket.dart';
import 'package:fennec_socket_io_server/server_io.dart';

void main(List<String> arguments) async {
  var io = ServerIO();
  var nsp = io.of('/some');
  nsp.on('connection', (client) {
    print('connection /some');
    client.on('msg', (data) {
      print('data from /some => $data');
      client.emit('fromServer', "ok 2");
    });
  });
  io.on('connection', (client) {
    print('connection default namespace');
    print(client);
    client.on('msg', (data) {
      print('data from default => $data');
      client.emit('fromServer', "ok");
    });
  });
  io.listen('0.0.0.0', 3000);
}
