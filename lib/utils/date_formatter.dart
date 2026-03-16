String _pad2(int v) => v.toString().padLeft(2, '0');

String formatDateTime(DateTime dt) {
  // dd/MM/yyyy HH:mm:ss
  return '${_pad2(dt.day)}/${_pad2(dt.month)}/${dt.year} '
      '${_pad2(dt.hour)}:${_pad2(dt.minute)}:${_pad2(dt.second)}';
}
