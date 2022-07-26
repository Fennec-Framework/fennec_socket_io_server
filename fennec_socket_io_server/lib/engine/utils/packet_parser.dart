// Protocol version
import 'dart:convert';
import 'dart:typed_data';

import 'wtf8.dart';

final protocol = 3;

enum PacketType { open, close, ping, pong, message, upgrade, noop }

const List<String?> packetTypeList = <String?>[
  'open',
  'close',
  'ping',
  'pong',
  'message',
  'upgrade',
  'noop'
];

const Map<String, int> packetTypeMap = <String, int>{
  'open': 0,
  'close': 1,
  'ping': 2,
  'pong': 3,
  'message': 4,
  'upgrade': 5,
  'noop': 6
};

class PacketParser {
  static const error = {'type': 'error', 'data': 'parser error'};
  static String? encodePacket(Map packet,
      {dynamic supportsBinary,
      utf8encode = false,
      required dynamic Function(dynamic t) callback,
      bool fromClient = false}) {
    if (supportsBinary is Function) {
      callback = supportsBinary as dynamic Function(dynamic);
      supportsBinary = null;
    }

    if (utf8encode is Function) {
      callback = utf8encode as dynamic Function(dynamic);
      utf8encode = null;
    }

    if (packet['data'] != null) {
      if (packet['data'] is Uint8List) {
        return encodeBuffer(packet, supportsBinary, callback,
            fromClient: fromClient);
      } else if (packet['data'] is Map &&
          (packet['data']['buffer'] != null &&
              packet['data']['buffer'] is ByteBuffer)) {
        packet['data'] = (packet['data']['buffer'] as ByteBuffer).asUint8List();
        return encodeBuffer(packet, supportsBinary, callback,
            fromClient: fromClient);
      } else if (packet['data'] is ByteBuffer) {
        packet['data'] = (packet['data'] as ByteBuffer).asUint8List();
        return encodeBuffer(packet, supportsBinary, callback,
            fromClient: fromClient);
      }
    }

    // Sending data as a utf-8 string
    var encoded = '''${packetTypeMap[packet['type']]}''';

    if (packet['data'] != null) {
      encoded += utf8encode == true
          ? WTF8.encode('''${packet['data']}''')
          : '''${packet['data']}''';
    }

    return callback(encoded);
  }

  static encodeBuffer(packet, supportsBinary, callback, {fromClient = false}) {
    if (!supportsBinary) {
      return encodeBase64Packet(packet, callback);
    }

    var data = packet['data'];
    // 'fromClient' is to check if the runtime is on server side or not,
    // because Dart server's websocket cannot send data with byte buffer.
    final newData = Uint8List(data.length + 1);
    newData
      ..setAll(0, [packetTypeMap[packet['type']]!]..length = 1)
      ..setAll(1, data);
    if (fromClient) {
      return callback(newData.buffer);
    } else {
      return callback(newData);
    }
  }

  static encodeBase64Packet(packet, callback) {
    var message = '''b${packetTypeMap[packet['type']]}''';
    message += base64.encode(packet.data.toString().codeUnits);
    return callback(message);
  }

  static decodePacket(dynamic data, {binaryType, required bool utf8decode}) {
    dynamic type;

    // String data
    if (data is String) {
      type = data[0];

      if (type == 'b') {
        return decodeBase64Packet((data).substring(1), binaryType);
      }

      if (utf8decode == true) {
        try {
          data = utf8.decode(data.codeUnits);
        } catch (e) {
          return error;
        }
      }
      if ('${int.parse(type)}' != type ||
          packetTypeList[type = int.parse(type)] == null) {
        return error;
      }

      if (data.length > 1) {
        return {'type': packetTypeList[type], 'data': data.substring(1)};
      } else {
        return {'type': packetTypeList[type]};
      }
    }

    // Binary data
    if (binaryType == 'arraybuffer' || data is ByteBuffer) {
      // wrap Buffer/ArrayBuffer data into an Uint8Array
      var intArray = (data as ByteBuffer).asUint8List();
      type = intArray[0];
      return {'type': packetTypeList[type], 'data': intArray.sublist(0)};
    }

//    if (data instanceof ArrayBuffer) {
//      data = arrayBufferToBuffer(data);
//    }
    type = data[0];
    return {'type': packetTypeList[type], 'data': data.sublist(1)};
  }

  static decodeBase64Packet(String msg, String binaryType) {
    var type = packetTypeList[msg.codeUnitAt(0)];
    var data = base64.decode(utf8.decode(msg.substring(1).codeUnits));
    if (binaryType == 'arraybuffer') {
      var abv = Uint8List(data.length);
      for (var i = 0; i < abv.length; i++) {
        abv[i] = data[i];
      }
      return {'type': type, 'data': abv.buffer};
    }
    return {'type': type, 'data': data};
  }

  static hasBinary(List packets) {
    return packets.any((map) {
      final data = map['data'];
      return data != null && data is ByteBuffer;
    });
  }

  static encodePayload(List packets,
      {bool supportsBinary = false,
      required dynamic Function(dynamic t) callback}) {
    if (supportsBinary && hasBinary(packets)) {
      return encodePayloadAsBinary(packets, callback);
    }

    if (packets.isEmpty) {
      return callback('0:');
    }

    encodeOne(packet, dynamic Function(dynamic t) doneCallback) {
      encodePacket(packet, supportsBinary: supportsBinary, utf8encode: false,
          callback: (message) {
        doneCallback(_setLengthHeader(message));
      });
    }

    map(packets, encodeOne, (results) {
      return callback(results.join(''));
    });
  }

  static _setLengthHeader(message) {
    return '${message.length}:$message';
  }

  static map(List ary, Function(dynamic _, Function(dynamic msg) callback) each,
      Function(dynamic results) done) {
    var result = [];
    Future.wait(ary.map((e) {
      return Future.microtask(() => each(e, (msg) {
            result.add(msg);
          }));
    })).then((r) => done(result));
  }

/*
 * Decodes data when a payload is maybe expected. Possible binary contents are
 * decoded from their base64 representation
 *
 * @param {String} data, callback method
 * @api public
 */

  static decodePayload(data,
      {bool binaryType = false,
      required Function(dynamic err, [dynamic foo, dynamic bar]) callback}) {
    if (data is! String) {
      return decodePayloadAsBinary(data,
          binaryType: binaryType, callback: callback);
    }

    if (data == '') {
      // parser error - ignoring payload
      return callback(Error, 0, 1);
    }

    dynamic packet = '', msg = '';
    dynamic length = 0, n = 0;

    for (int i = 0, l = data.length; i < l; i++) {
      var chr = data[i];

      if (chr != ':') {
        length += chr;
        continue;
      }

      if (length.isEmpty || (length != '${(n = num.tryParse(length))}')) {
        // parser error - ignoring payload
        return callback(error, 0, 1);
      }

      int nv = n!;
      msg = data.substring(i + 1, i + 1 + nv);

      if (length != '${msg.length}') {
        // parser error - ignoring payload
        return callback(error, 0, 1);
      }

      if (msg.isNotEmpty) {
        packet = decodePacket(msg, binaryType: binaryType, utf8decode: false);

        if (error['type'] == packet['type'] &&
            error['data'] == packet['data']) {
          // parser error in individual packet - ignoring payload
          return callback(error, 0, 1);
        }

        var more = callback(packet, i + nv, l);
        if (false == more) return null;
      }

      // advance cursor
      i += nv;
      length = '';
    }

    if (length.isNotEmpty) {
      // parser error - ignoring payload
      return callback(error, 0, 1);
    }
  }

  static decodePayloadAsBinary(List<int> data,
      {bool? binaryType,
      required Function(dynamic err, [dynamic foo, dynamic bar]) callback}) {
    var bufferTail = data;
    var buffers = [];
    int i;

    while (bufferTail.isNotEmpty) {
      var strLen = '';
      var isString = bufferTail[0] == 0;
      for (i = 1;; i++) {
        if (bufferTail[i] == 255) break;
        // 310 = char length of Number.MAX_VALUE
        if (strLen.length > 310) {
          return callback(error, 0, 1);
        }
        strLen += '${bufferTail[i]}';
      }
      bufferTail = bufferTail.skip(strLen.length + 1).toList();

      var msgLength = int.parse(strLen);

      dynamic msg = bufferTail.getRange(1, msgLength + 1);
      if (isString == true) msg = String.fromCharCodes(msg);
      buffers.add(msg);
      bufferTail = bufferTail.skip(msgLength + 1).toList();
    }

    var total = buffers.length;
    for (i = 0; i < total; i++) {
      var buffer = buffers[i];
      callback(decodePacket(buffer, binaryType: binaryType, utf8decode: true),
          i, total);
    }
  }

  static encodePayloadAsBinary(List packets, Function(dynamic _) callback) {
    if (packets.isEmpty) {
      return callback(Uint8List(0));
    }

    map(packets, encodeOneBinaryPacket, (results) {
      var list = [];
      results.forEach((e) => list.addAll(e));
      return callback(list);
    });
  }

  static encodeOneBinaryPacket(p, Function(dynamic _) doneCallback) {
    onBinaryPacketEncode(dynamic packet) {
      var encodingLength = '${packet.length}';
      Uint8List sizeBuffer;

      if (packet is String) {
        sizeBuffer = Uint8List(encodingLength.length + 2);
        sizeBuffer[0] = 0; // is a string (not true binary = 0)
        for (var i = 0; i < encodingLength.length; i++) {
          sizeBuffer[i + 1] = int.parse(encodingLength[i]);
        }
        sizeBuffer[sizeBuffer.length - 1] = 255;
        return doneCallback(
            List.from(sizeBuffer)..addAll(stringToBuffer(packet)));
      }

      sizeBuffer = Uint8List(encodingLength.length + 2);
      sizeBuffer[0] = 1; // is binary (true binary = 1)
      for (var i = 0; i < encodingLength.length; i++) {
        sizeBuffer[i + 1] = int.parse(encodingLength[i]);
      }
      sizeBuffer[sizeBuffer.length - 1] = 255;

      doneCallback(List.from(sizeBuffer)..addAll(packet));
    }

    encodePacket(p,
        supportsBinary: true, utf8encode: true, callback: onBinaryPacketEncode);
  }

  static List<int> stringToBuffer(String string) {
    var buf = Uint8List(string.length);
    for (var i = 0, l = string.length; i < l; i++) {
      buf[i] = string.codeUnitAt(i);
    }
    return buf;
  }
}
