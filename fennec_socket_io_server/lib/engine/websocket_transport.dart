import 'dart:async';

import 'package:fennec_socket_io_server/engine/transports.dart';

import 'utils/packet_parser.dart';

class WebSocketTransport extends Transport {
  @override
  bool get handlesUpgrades => true;
  @override
  bool get supportsFraming => true;
  StreamSubscription? subscription;
  WebSocketTransport(connect) : super(connect) {
    name = 'websocket';
    this.connect = connect;
    subscription =
        connect.websocket.listen(onData, onError: onError, onDone: onClose);
    writable = true;
  }

  @override
  void send(List<Map> data) {
    send(data, Map packet) {
      connect!.websocket?.add(data);
    }

    for (var i = 0; i < data.length; i++) {
      var packet = data[i];
      PacketParser.encodePacket(packet,
          supportsBinary: supportsBinary, callback: (_) => send(_, packet));
    }
  }

  @override
  void onClose() {
    super.onClose();

    // workaround for https://github.com/dart-lang/sdk/issues/27414
    if (subscription != null) {
      subscription!.cancel();
      subscription = null;
    }
  }

  @override
  void doClose([callback]) {
    connect!.websocket?.close();
    if (callback != null) callback();
  }
}
