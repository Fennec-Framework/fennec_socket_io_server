import 'dart:typed_data';

///[Binary]
class Binary {
  static final String keyPlaceholder = "_placeholder";

  static final String keyNum = "num";

  static Map deconstructPacket(Map packet) {
    List buffers = [];

    packet['data'] = _deconstructPacket(packet['data'], buffers);
    packet['attachments'] = buffers.length;

    final result = {'packet': packet, 'buffers': buffers};
    return result;
  }

  static Object? _deconstructPacket(Object? data, List buffers) {
    if (data == null) return null;

    if (data is Uint8List) {
      final placeholder = {keyPlaceholder: true, keyNum: buffers.length};
      buffers.add(data);
      return placeholder;
    } else if (data is List) {
      final newData = [];
      final _data = data;
      int len = _data.length;
      for (int i = 0; i < len; i++) {
        newData.add(_deconstructPacket(_data[i], buffers));
      }
      return newData;
    } else if (data is Map) {
      final newData = {};
      final _data = data;
      data.forEach((k, v) {
        newData[k] = _deconstructPacket(_data[k], buffers);
      });
      return newData;
    }
    return data;
  }

  static Map reconstructPacket(Map packet, List<List<int>> buffers) {
    packet['data'] = _reconstructPacket(packet['data'], buffers);
    packet['attachments'] = -1;
    return packet;
  }

  static Object? _reconstructPacket(Object data, List<List<int>> buffers) {
    if (data is List) {
      final _data = data;
      int i = 0;
      for (var v in _data) {
        _data[i++] = _reconstructPacket(v, buffers);
      }
      return _data;
    } else if (data is Map) {
      final _data = data;
      if ('${_data[keyPlaceholder]}'.toLowerCase() == 'true') {
        final knum = _data[keyNum]!;
        int num = knum is int ? knum : int.parse(knum).toInt();
        return num >= 0 && num < buffers.length ? buffers[num] : null;
      }
      data.forEach((key, value) {
        _data[key] = _reconstructPacket(value, buffers);
      });
      return _data;
    }
    return data;
  }
}
