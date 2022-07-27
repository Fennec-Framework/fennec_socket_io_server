import 'dart:convert';
import 'dart:typed_data';

import 'binary.dart';
import 'entity_emitter.dart';

const int connectValue = 0;
const int disconnectValue = 1;
const int eventValue = 2;
const int ackValue = 3;
const int errorValue = 4;
const int binaryEventValue = 5;
const int binaryAckValue = 6;

List<String?> packetTypes = <String?>[
  'CONNECT',
  'DISCONNECT',
  'EVENT',
  'ACK',
  'ERROR',
  'BINARY_EVENT',
  'BINARY_ACK'
];

class Encoder {
  encode(obj, callback) {
    if (binaryEventValue == obj['type'] || binaryAckValue == obj['type']) {
      encodeAsBinary(obj, callback);
    } else {
      var encoding = encodeAsString(obj);
      callback([encoding]);
    }
  }

  static String encodeAsString(obj) {
    var str = '${obj['type']}';

    if (binaryEventValue == obj['type'] || binaryAckValue == obj['type']) {
      str += '${obj['attachments']}-';
    }

    if (obj['nsp'] != null && '/' != obj['nsp']) {
      str += obj['nsp'] + ',';
    }

    if (null != obj['id']) {
      str += '${obj['id']}';
    }

    if (null != obj['data']) {
      str += json.encode(obj['data']);
    }

    return str;
  }

  static encodeAsBinary(obj, callback) {
    writeEncoding(bloblessData) {
      var deconstruction = Binary.deconstructPacket(bloblessData);
      var pack = encodeAsString(deconstruction['packet']);
      var buffers = deconstruction['buffers'];

      callback(<dynamic>[pack, ...buffers]); // write all the buffers
    }

    writeEncoding(obj);
  }
}

class Decoder extends EventEmitter {
  dynamic reconstructor;

  add(obj) {
    dynamic packet;
    if (obj is String) {
      packet = decodeString(obj);
      if (binaryEventValue == packet['type'] ||
          binaryAckValue == packet['type']) {
        reconstructor = BinaryReconstructor(packet);

        if (reconstructor.reconPack['attachments'] == 0) {
          emit('decoded', packet);
        }
      } else {
        emit('decoded', packet);
      }
    } else if ((obj != null && obj is ByteBuffer) ||
        obj is Uint8List ||
        obj is Map && obj['base64'] != null) {
      if (reconstructor == null) {
        throw UnsupportedError(
            'got binary data when not reconstructing a packet');
      } else {
        packet = reconstructor.takeBinaryData(obj);
        if (packet != null) {
          reconstructor = null;
          emit('decoded', packet);
        }
      }
    } else {
      throw UnsupportedError('Unknown type: ' + obj);
    }
  }

  static decodeString(String str) {
    var i = 0;
    var endLen = str.length - 1;

    var p = <String, dynamic>{'type': num.parse(str[0])};

    if (null == packetTypes[p['type']]) return error();

    if (binaryEventValue == p['type'] || binaryAckValue == p['type']) {
      var buf = '';
      while (str[++i] != '-') {
        buf += str[i];
        if (i == endLen) break;
      }
      if (buf != '${num.tryParse(buf) ?? -1}' || str[i] != '-') {
        throw ArgumentError('Illegal attachments');
      }
      p['attachments'] = num.parse(buf);
    }

    if (str.length > i + 1 && '/' == str[i + 1]) {
      p['nsp'] = '';
      while (++i > 0) {
        var c = str[i];
        if (',' == c) break;
        p['nsp'] += c;
        if (i == endLen) break;
      }
    } else {
      p['nsp'] = '/';
    }

    var next = i < endLen - 1 ? str[i + 1] : null;
    if (next?.isNotEmpty == true && '${num.tryParse(next!)}' == next) {
      p['id'] = '';
      while (++i > 0) {
        var c = str[i];
        if ('${num.tryParse(c)}' != c) {
          --i;
          break;
        }
        p['id'] += str[i];
        if (i == endLen - 1) break;
      }
    }

    if (i < endLen - 1 && str[++i].isNotEmpty == true) {
      p = tryParse(p, str.substring(i));
    }

    return p;
  }

  static tryParse(p, str) {
    try {
      p['data'] = json.decode(str);
    } catch (e) {
      return error();
    }
    return p;
  }

  destroy() {
    if (reconstructor != null) {
      reconstructor.finishedReconstruction();
    }
  }
}

class BinaryReconstructor {
  late Map? reconPack;
  List buffers = [];
  BinaryReconstructor(packet) {
    reconPack = packet;
  }

  takeBinaryData(binData) {
    buffers.add(binData);
    if (buffers.length == reconPack!['attachments']) {
      // done with buffer list

      var packet =
          Binary.reconstructPacket(reconPack!, buffers.cast<List<int>>());

      finishedReconstruction();
      return packet;
    }
    return null;
  }

  void finishedReconstruction() {
    reconPack = null;
    buffers = [];
  }
}

Map error() {
  return {'type': errorValue, 'data': 'parser error'};
}
