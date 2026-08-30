import 'dart:typed_data';

/// Minimal decoder for the small subset of bencode a tracker scrape
/// reply actually uses — dictionaries, byte strings, integers.
/// Deliberately not a pub dependency: this only ever needs to read a
/// scrape response, never write bencode or touch .torrent files
/// themselves (libtorrent_flutter already owns that).
class BencodeReader {
  final Uint8List _data;
  int _pos = 0;

  BencodeReader(this._data);

  dynamic readValue() {
    final marker = _data[_pos];
    if (marker == 0x64) return _readDict(); // 'd'
    if (marker == 0x6c) return _readList(); // 'l'
    if (marker == 0x69) return _readInt(); // 'i'
    return _readByteString(); // starts with an ASCII digit
  }

  Map<String, dynamic> _readDict() {
    _pos++; // skip 'd'
    final map = <String, dynamic>{};
    while (_data[_pos] != 0x65 /* 'e' */ ) {
      final key = String.fromCharCodes(_readByteString());
      map[key] = readValue();
    }
    _pos++; // skip 'e'
    return map;
  }

  List<dynamic> _readList() {
    _pos++; // skip 'l'
    final list = <dynamic>[];
    while (_data[_pos] != 0x65) {
      list.add(readValue());
    }
    _pos++; // skip 'e'
    return list;
  }

  int _readInt() {
    _pos++; // skip 'i'
    final start = _pos;
    while (_data[_pos] != 0x65) {
      _pos++;
    }
    final value = int.parse(String.fromCharCodes(_data.sublist(start, _pos)));
    _pos++; // skip 'e'
    return value;
  }

  Uint8List _readByteString() {
    final start = _pos;
    while (_data[_pos] != 0x3a /* ':' */ ) {
      _pos++;
    }
    final length = int.parse(String.fromCharCodes(_data.sublist(start, _pos)));
    _pos++; // skip ':'
    final bytes = _data.sublist(_pos, _pos + length);
    _pos += length;
    return bytes;
  }
}

String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List hexDecode(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}
