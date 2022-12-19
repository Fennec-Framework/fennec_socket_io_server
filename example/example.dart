import 'dart:async';
import 'dart:io';

import 'package:fennec/fennec.dart';
import 'package:fennec_socket_io_server/server_io.dart';

void main(List<String> arguments) async {
  /// Connect SOCKET IO Server with Fennec HTTP Server
  StreamController<HttpRequest> streamController = StreamController();
  Application application = Application();
  application.setNumberOfIsolates(1);
  List<dynamic> clients = [];
  ServerIO serverIO = ServerIO();
  ServerIO serverIO1 = ServerIO();
  application.setPort(8000).setHost('0.0.0.0');
  application.get(
    path: '/dynamic_routes/@userId',
    requestHandler: (context, req, res) {
      serverIO.emit('fromServer', DateTime.now().toIso8601String());
      return res.ok(body: {'userId': req.pathParams['userId']}).json();
    },
  );

  Router testRouter = Router(routerPath: '/v1/api');

  testRouter.get(
    path: '/simple1',
    requestHandler: (ServerContext context, Request req, Response res) {
      for (var i = 0; i < 7; i++) {
        serverIO.emit('message', 'JACK AISSA');
      }
      serverIO1.emit('message', 'JACK AISSA');
      return res.ok(body: 'ss');
    },
  );

  application.useWebSocket(true);
  application.addRouter(testRouter);
  application.socketIO(socketIOHandler: (context, ws) {
    streamController.sink.add(ws);
  });
  await serverIO.listenToHttpServer(streamController);
  await application.runServer();

  /// run SOCKET IO Server as own Server

  serverIO1.on('connection', (client) {
    print('connection');
    serverIO1.emit('fromServer', 'ok');
  });

  await serverIO1.listen('0.0.0.0', 3000);
}
