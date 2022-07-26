import 'package:fennec_socket_io_server/server_io.dart';
import 'package:fennec_socket_io_server/socket_io_config.dart';

void main(List<String> arguments) async {
  var io = ServerIO(SocketIOConfig('0.0.0.0', 8000));

  /* io.on('connection', (client) {
    print('connection /some');
    /* client.on('error', (data) {
      print('s');
    });*/

    /* client.on('msg', (data) {
      print('data from /some => $data');
      client.emit('fromServer', "ok 2");
    });*/
  });*/

  await io.listen();
  await Future.delayed(Duration(seconds: 5));
  //io.emit('123', 'ette');
}
