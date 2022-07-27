import 'polling_transport.dart';
import 'socket_connect.dart';

class XHRTransport extends PollingTransport {
  XHRTransport(SocketConnect connect) : super(connect);

  /// Overrides `onRequest` to handle `OPTIONS`..

  @override
  void onRequest(SocketConnect connect) {
    var req = connect.request;
    if ('OPTIONS' == req.method) {
      var res = req.response;
      var headers = this.headers(connect);
      headers['Access-Control-Allow-Headers'] = 'Content-Type';
      headers.forEach((key, value) {
        res.headers.set(key, value);
      });
      res.statusCode = 200;

      connect.close();
    } else {
      super.onRequest(connect);
    }
  }

  /// Returns headers for a response.
  @override
  Map headers(SocketConnect connect, [Map? headers]) {
    headers = headers ?? {};
    var req = connect.request;
    if (req.headers.value('origin') != null) {
      headers['Access-Control-Allow-Credentials'] = 'true';
      headers['Access-Control-Allow-Origin'] = req.headers.value('origin');
    } else {
      headers['Access-Control-Allow-Origin'] = '*';
    }
    return super.headers(connect, headers);
  }
}
