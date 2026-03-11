import 'package:intl/intl.dart';

final NumberFormat _f = NumberFormat("#,##0");

extension XNum on num {
  String readableFileSize({bool base1024 = true}) {
    int base = base1024 ? 1024 : 1000;
    if (this <= 0) return "0";
    List<String> units = ["B", "KB", "MB", "GB", "TB", "PB"];
    int digitGroups = 0;
    num size = this;

    while (size >= base && digitGroups < units.length - 1) {
      size = size / base;
      digitGroups++;
    }

    return "${_f.format(size)} ${units[digitGroups]}";
  }
}
