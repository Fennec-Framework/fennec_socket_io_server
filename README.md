**fennec_socket_io_server** is dart plugin to implement SOCKET IO for the server side. it belongs to fennec framework [pub.dev](https://pub.dev/packages/fennec) but it can be used
separately.

# Installation

install the plugin from [pub.dev](https://pub.dev/packages/fennec_socket_io_server)

# Example with own HTTP Server.

```dart
ServerIO serverIO1 = ServerIO();
serverIO1.on('connection', (client) {
print('connection');
serverIO1.emit('fromServer', 'ok');
});

await serverIO1.listen('0.0.0.0', 3000);

```

# Example with Fennec HTTP Server.

```dart
 Application application = Application();
 ServerIO serverIO = ServerIO();
 application.setPort(8000).setHost(InternetAddress.loopbackIPv4);
 application.get(
     path: '/dynamic_routes/@userId',
     requestHandler: (req, res) {
       serverIO.emit('fromServer', DateTime.now().toIso8601String());
       res.json({'userId': req.pathParams['userId']});
     },
     middlewares: []);

 Router testRouter = Router(routerPath: '/v1/api');
 testRouter.get(
     path: '/simple', requestHandler: TestController().test, middlewares: []);
 testRouter.get(
   path: '/simple1',
   requestHandler: (Request req, Response res) {
     serverIO.emit('message', 'hello fennec');
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

```

# License

[MIT](https://github.com/Fennec-Framework/fennec_socket_io_server/blob/master/LICENSE)
