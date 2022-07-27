import 'dart:io';

import 'package:fennec/fennec.dart';
import 'package:fennec_socket_io_server/server_io.dart';

void main(List<String> arguments) async {
  /// Connect SOCKET IO Server with Fennec HTTP Server
  Application application = Application();
  ServerIO serverIO = ServerIO();
  application.setPort(8000).setHost(InternetAddress.loopbackIPv4);
  application.get(
    path: '/dynamic_routes/@userId',
    requestHandler: (req, res) {
      serverIO.emit('fromServer', DateTime.now().toIso8601String());
      res.json({'userId': req.pathParams['userId']});
    },
  );

  Router testRouter = Router(routerPath: '/v1/api');

  testRouter.get(
    path: '/simple1',
    requestHandler: (Request req, Response res) {
      serverIO.emit('message', 'JACK AISSA');
      res.send('ss');
    },
  );

  application.useSocketIOServer(true);

  Server server = Server(application);
  await server.startServer();

  serverIO.on('connection', (client) {
    print('coo');
  });

  await serverIO.listenToHttpServer(server.httpServerStream);

  /// run SOCKET IO Server as own Server
  ServerIO serverIO1 = ServerIO();
  serverIO1.on('connection', (client) {
    print('connection');
    serverIO1.emit('fromServer', 'ok');
  });

  await serverIO1.listen('0.0.0.0', 3000);
}
