///[WTF8]
class WTF8 {
  static String encode(String string) {
    var codePoints = _ucs2decode(string);
    var length = codePoints.length;
    var index = -1;
    int codePoint;
    var byteString = '';
    while (++index < length) {
      codePoint = codePoints[index];
      byteString += _encodeCodePoint(codePoint);
    }
    return byteString;
  }

  static List<int> _ucs2decode(String string) {
    List<int> output = [];
    var counter = 0;
    var length = string.length;
    int value;
    int extra;
    while (counter < length) {
      value = string.codeUnitAt(counter++);
      if (value >= 0xD800 && value <= 0xDBFF && counter < length) {
        extra = string.codeUnitAt(counter++);
        if ((extra & 0xFC00) == 0xDC00) {
          output.add(((value & 0x3FF) << 10) + (extra & 0x3FF) + 0x10000);
        } else {
          output.add(value);
          counter--;
        }
      } else {
        output.add(value);
      }
    }
    return output;
  }

  static _encodeCodePoint(int codePoint) {
    if ((codePoint & 0xFFFFFF80) == 0) {
      return String.fromCharCode(codePoint);
    }
    var symbol = '';
    if ((codePoint & 0xFFFFF800) == 0) {
      symbol = String.fromCharCode(((codePoint >> 6) & 0x1F) | 0xC0);
    } else if ((codePoint & 0xFFFF0000) == 0) {
      symbol = String.fromCharCode(((codePoint >> 12) & 0x0F) | 0xE0);
      symbol += _createByte(codePoint, 6);
    } else if ((codePoint & 0xFFE00000) == 0) {
      symbol = String.fromCharCode(((codePoint >> 18) & 0x07) | 0xF0);
      symbol += _createByte(codePoint, 12);
      symbol += _createByte(codePoint, 6);
    }
    symbol += String.fromCharCode((codePoint & 0x3F) | 0x80);
    return symbol;
  }

  static _createByte(codePoint, shift) {
    return String.fromCharCode(((codePoint >> shift) & 0x3F) | 0x80);
  }
}
