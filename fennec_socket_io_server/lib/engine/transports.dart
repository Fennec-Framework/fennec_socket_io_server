import '../utils/entity_emitter.dart';
import 'jsonp_transport.dart';
import 'socket_connect.dart';
import 'utils/packet_parser.dart';
import 'websocket_transport.dart';
import 'xhr_transport.dart';

class Transports {
  static List<String> upgradesTo(String from) {
    if ('polling' == from) {
      return ['websocket'];
    }
    return [];
  }

  static Transport newInstance(String name, SocketConnect connect) {
    if ('websocket' == name) {
      return WebSocketTransport(connect);
    } else if ('polling' == name) {
      if (connect.request.uri.queryParameters.containsKey('j')) {
        return JSONPTransport(connect);
      } else {
        return XHRTransport(connect);
      }
    } else {
      throw UnsupportedError('Unknown transport $name');
    }
  }
}

abstract class Transport extends EventEmitter {
  double? maxHttpBufferSize;
  Map? httpCompression;
  Map? perMessageDeflate;
  bool? supportsBinary;
  String? sid;
  String? name;
  bool? writable;
  String readyState = 'open';
  bool discarded = false;
  SocketConnect? connect;
  MessageHandler? messageHandler;

  Transport(connect) {
    var options = connect.dataset['options'];
    if (options != null) {
      messageHandler = options.containsKey('messageHandlerFactory')
          ? options['messageHandlerFactory'](this, connect)
          : null;
    }
  }

  void discard() {
    discarded = true;
  }

  void onRequest(SocketConnect connect) {
    this.connect = connect;
  }

  void close([dynamic Function()? closeFn]) {
    if ('closed' == readyState || 'closing' == readyState) return;
    readyState = 'closing';
    doClose(closeFn);
  }

  void doClose([dynamic Function()? callback]);

  void onError(msg, [desc]) {
    writable = false;
    if (hasListeners('error')) {
      emit('error', {'msg': msg, 'desc': desc, 'type': 'TransportError'});
    } else {}
  }

  void onPacket(Map packet) {
    emit('packet', packet);
  }

  void onData(data) {
    if (messageHandler != null) {
      messageHandler!.handle(this, data);
    } else {
      onPacket(PacketParser.decodePacket(data, utf8decode: true));
    }
  }

  void onClose() {
    readyState = 'closed';
    emit('close');
  }

  void send(List<Map> data);

  bool get supportsFraming;
  bool get handlesUpgrades;
}

abstract class MessageHandler {
  void handle(Transport transport, /*String|List<int>*/ message);
}
