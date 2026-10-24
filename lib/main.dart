// FileShare Android - سازگار با نسخه دسکتاپ (file_share_v4.py)
// پروتکل: TCP پورت 50505 | هر پیام = 4 بایت طول (big-endian) + JSON (UTF-8)
// hello:  {"type":"hello"} -> {"name": "..."}
// file:   {"type":"file","name":rel,"size":n,"from":..,"batch":..,"count":n,"total":n}
//         -> {"ok":true} | {"ok":false,"reason":"not_receiving"|"rejected"}
//         سپس n بایت فایل و در پایان {"done":true}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const kBorder = Color(0xFF1E88E5);
const kBg = Color(0xFFF5F9FF);
const kGreen = Color(0xFF2E7D32);
const kBlue = Color(0xFF1565C0);
const kOrange = Color(0xFFEF6C00);
const kRed = Color(0xFFC62828);
const kPurple = Color(0xFF6A1B9A);
const kGray = Color(0xFF546E7A);
const int kChunk = 64 * 1024;

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> msgKey = GlobalKey<ScaffoldMessengerState>();

// ---------------------------------------------------------------- ترجمه‌ها
const Map<String, Map<String, String>> T = {
  'fa': {
    'title': 'انتقال فایل',
    'me': 'دستگاه من: {name} | IP: {ip} | پورت: {port}',
    'mode_on': '● حالت دریافت فعال',
    'mode_off': '○ حالت ارسال',
    'tab_send': 'ارسال',
    'tab_recv': 'دریافت',
    'tab_hist': 'تاریخچه',
    'tab_fav': 'پرکاربرد',
    'receiver': 'گیرنده',
    'scan': '🔍 جستجو در شبکه',
    'manual_ip': 'IP دستی',
    'add_fav': '⭐ افزودن به پرکاربرد',
    'files_box': 'فایل‌ها و پوشه‌ها',
    'add_files': '➕ افزودن فایل',
    'remove_sel': '🗑 حذف انتخاب‌شده',
    'count': '{items} مورد - {files} فایل - مجموع {size}',
    'count_wait': '{items} مورد - در حال محاسبه...',
    'send': '🚀 ارسال',
    'b_title': 'انتخاب فایل و پوشه',
    'b_sel_all': '☑ انتخاب همه',
    'b_desel': '☐ حذف انتخاب‌ها',
    'b_add': '➕ افزودن',
    'b_selected': 'انتخاب‌شده: {n}',
    'b_hint': 'برای باز شدن پوشه روی آن بزنید. مربع سبز را بزنید تا انتخاب شود. برای منو، نگه دارید.',
    'internal': 'حافظه داخلی',
    'dir_send': 'ارسال',
    'dir_recv': 'دریافت',
    'st_ok': 'موفق',
    'st_fail': 'ناموفق',
    'st_rej': 'رد شد',
    'r_on': '● حالت دریافت فعال - منتظر فایل...\nIP: {ip} | پورت: {port}',
    'r_off': '○ حالت دریافت خاموش - دستگاه‌های دیگر شما را پیدا نمی‌کنند',
    'r_start': '▶ شروع دریافت',
    'r_stop': '⏹ توقف دریافت',
    'recv_folder': '📂 پوشه دریافت',
    'h_clear': '🧹 پاک کردن تاریخچه',
    'f_add': '➕ افزودن',
    'f_rename': '✏ تغییر نام',
    'ready': 'آماده',
    'empty': 'خالی است',
    'm_remove': 'حذف از لیست ارسال',
    'm_select_all': 'انتخاب همه',
    'm_deselect': 'حذف همه انتخاب‌ها',
    'm_copy': 'کپی مسیر',
    'm_toggle': 'انتخاب / لغو انتخاب',
    'm_expand': 'باز/بسته کردن پوشه',
    'm_open': 'باز کردن',
    'm_reveal': 'نمایش محل',
    'm_delete_list': 'حذف از لیست',
    'm_delete_disk': 'حذف فایل از حافظه',
    'm_use': 'استفاده برای ارسال',
    'm_copy_ip': 'کپی IP',
    'confirm_disk': '{n} فایل برای همیشه حذف شود؟ (قابل بازگشت نیست)',
    'w_no_recv': 'گیرنده را انتخاب کنید یا IP را وارد کنید.',
    'w_no_files': 'فایلی انتخاب نشده است.',
    'no_file': 'فایل یافت نشد.',
    'confirm_clear': 'کل تاریخچه پاک شود؟',
    'fav_name': 'نام مخاطب',
    'fav_ip': 'آدرس IP',
    'fav_new': 'نام جدید',
    'w_dup': 'قبلاً اضافه شده است.',
    'w_pick_ip': 'ابتدا IP یا گیرنده را مشخص کنید.',
    'scanning': 'در حال جستجوی دستگاه‌ها...',
    'scan_done': 'جستجو پایان یافت',
    'sending': 'ارسال {i}/{n}: {name}',
    'send_done': 'ارسال تمام شد',
    'receiving': 'دریافت از {s}: {name}',
    'recv_ok': '✔ دریافت شد: {name}',
    'send_err': 'خطا در ارسال {name}: {e}',
    'recv_err': 'خطا در دریافت: {e}',
    'rejected': 'گیرنده فایل را نپذیرفت',
    'not_receiving': 'دستگاه مقابل در حالت دریافت نیست (باید تب دریافت را باز کند)',
    'ask_title': 'درخواست دریافت فایل',
    'ask_text': '{sender} ({ip}) می‌خواهد {count} فایل به حجم {total} برای شما بفرستد.\n\nنام فایل: {name}\n\nدریافت شود؟',
    'accept': 'قبول',
    'reject': 'رد',
    'got_title': 'دریافت انجام شد',
    'got_text': '{n} فایل از {peer} دریافت شد.',
    'open_file': '📄 باز کردن فایل',
    'open_folder': '📂 نمایش محل',
    'close': 'بستن',
    'copy': 'کپی',
    'copied': 'کپی شد',
    'location': 'محل فایل',
    'yes': 'بله',
    'no': 'خیر',
    'st_title': 'تنظیمات',
    'lang': 'زبان',
    'recv_dir': 'پوشه دریافت',
    'port': 'پورت',
    'ip': 'IP این دستگاه (خالی = خودکار)',
    'name': 'نام دستگاه',
    'note': 'پورت باید روی هر دو دستگاه یکسان باشد.',
    'save': '💾 ذخیره',
    'cancel': 'انصراف',
    'bad_port': 'پورت باید عددی بین 1024 تا 65535 باشد.',
    'perm_needed': 'برای دیدن فایل‌ها باید «دسترسی به همه فایل‌ها» را بدهید.',
  },
  'en': {
    'title': 'FileShare',
    'me': 'My device: {name} | IP: {ip} | Port: {port}',
    'mode_on': '● Receive mode ON',
    'mode_off': '○ Send mode',
    'tab_send': 'Send',
    'tab_recv': 'Receive',
    'tab_hist': 'History',
    'tab_fav': 'Favorites',
    'receiver': 'Receiver',
    'scan': '🔍 Scan network',
    'manual_ip': 'Manual IP',
    'add_fav': '⭐ Add to favorites',
    'files_box': 'Files and folders',
    'add_files': '➕ Add file',
    'remove_sel': '🗑 Remove selected',
    'count': '{items} item(s) - {files} file(s) - total {size}',
    'count_wait': '{items} item(s) - calculating...',
    'send': '🚀 Send',
    'b_title': 'Select files and folders',
    'b_sel_all': '☑ Select all',
    'b_desel': '☐ Deselect all',
    'b_add': '➕ Add',
    'b_selected': 'Selected: {n}',
    'b_hint': 'Tap a folder to open it. Tap the green square to select. Long-press for a menu.',
    'internal': 'Internal storage',
    'dir_send': 'Sent',
    'dir_recv': 'Received',
    'st_ok': 'OK',
    'st_fail': 'Failed',
    'st_rej': 'Rejected',
    'r_on': '● Receive mode ON - waiting for files...\nIP: {ip} | Port: {port}',
    'r_off': '○ Receive mode OFF - other devices cannot find you',
    'r_start': '▶ Start receiving',
    'r_stop': '⏹ Stop receiving',
    'recv_folder': '📂 Received folder',
    'h_clear': '🧹 Clear history',
    'f_add': '➕ Add',
    'f_rename': '✏ Rename',
    'ready': 'Ready',
    'empty': 'Empty',
    'm_remove': 'Remove from send list',
    'm_select_all': 'Select all',
    'm_deselect': 'Deselect all',
    'm_copy': 'Copy path',
    'm_toggle': 'Select / Unselect',
    'm_expand': 'Expand / Collapse folder',
    'm_open': 'Open',
    'm_reveal': 'Show location',
    'm_delete_list': 'Delete from list',
    'm_delete_disk': 'Delete file from storage',
    'm_use': 'Use for sending',
    'm_copy_ip': 'Copy IP',
    'confirm_disk': 'Permanently delete {n} file(s)? This cannot be undone.',
    'w_no_recv': 'Select a receiver or enter an IP.',
    'w_no_files': 'No files selected.',
    'no_file': 'File not found.',
    'confirm_clear': 'Clear the whole history?',
    'fav_name': 'Contact name',
    'fav_ip': 'IP address',
    'fav_new': 'New name',
    'w_dup': 'Already added.',
    'w_pick_ip': 'Select a receiver or enter an IP first.',
    'scanning': 'Scanning for devices...',
    'scan_done': 'Scan finished',
    'sending': 'Sending {i}/{n}: {name}',
    'send_done': 'Sending finished',
    'receiving': 'Receiving from {s}: {name}',
    'recv_ok': '✔ Received: {name}',
    'send_err': 'Error sending {name}: {e}',
    'recv_err': 'Receive error: {e}',
    'rejected': 'The receiver rejected the file',
    'not_receiving': 'The other device is not in receive mode (it must open the Receive tab)',
    'ask_title': 'Incoming file request',
    'ask_text': '{sender} ({ip}) wants to send you {count} file(s), total {total}.\n\nFile name: {name}\n\nAccept?',
    'accept': 'Accept',
    'reject': 'Reject',
    'got_title': 'Transfer complete',
    'got_text': '{n} file(s) received from {peer}.',
    'open_file': '📄 Open file',
    'open_folder': '📂 Show location',
    'close': 'Close',
    'copy': 'Copy',
    'copied': 'Copied',
    'location': 'File location',
    'yes': 'Yes',
    'no': 'No',
    'st_title': 'Settings',
    'lang': 'Language',
    'recv_dir': 'Receive folder',
    'port': 'Port',
    'ip': 'This device IP (empty = automatic)',
    'name': 'Device name',
    'note': 'The port must be the same on both devices.',
    'save': '💾 Save',
    'cancel': 'Cancel',
    'bad_port': 'Port must be a number between 1024 and 65535.',
    'perm_needed': 'Please grant "All files access" to browse files.',
  },
};

String fmt(String s, Map<String, Object> m) {
  m.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

String human(int n) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  double v = n.toDouble();
  int i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(1)} ${u[i]}';
}

String _norm(String s) => (s.length > 1 && s.endsWith('/')) ? s.substring(0, s.length - 1) : s;

bool isUnder(String child, String parent) {
  final c = _norm(child), p = _norm(parent);
  return c != p && c.startsWith(p.endsWith('/') ? p : '$p/');
}

String uniquePath(String folder, String name) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var p = '$folder/$name';
  var i = 1;
  while (File(p).existsSync()) {
    p = '$folder/$base ($i)$ext';
    i++;
  }
  return p;
}

// ---------------------------------------------------------------- مدل‌ها
class Entry {
  String id, time, file, dir, peer, path, status;
  Entry({required this.id, required this.time, required this.file, required this.dir,
      required this.peer, required this.path, required this.status});
  Map<String, dynamic> toJson() => {
        'id': id, 'time': time, 'file': file, 'dir': dir, 'peer': peer, 'path': path, 'status': status
      };
  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: (j['id'] ?? DateTime.now().microsecondsSinceEpoch).toString(),
        time: (j['time'] ?? '').toString(),
        file: (j['file'] ?? '').toString(),
        dir: (j['dir'] ?? '').toString(),
        peer: (j['peer'] ?? '').toString(),
        path: (j['path'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
      );
}

class Fav {
  String name, ip;
  Fav(this.name, this.ip);
}

class SendItem {
  final String path;
  final bool isDir;
  SendItem(this.path, this.isDir);
}

class Pair {
  final String path, rel;
  Pair(this.path, this.rel);
}

class TNode {
  final String name, path;
  final bool isDir;
  final int depth;
  String size;
  bool expanded = false, loaded = false;
  List<TNode> kids = [];
  TNode(this.name, this.path, this.isDir, this.depth, {this.size = ''});
}

// ---------------------------------------------------------------- خواندن سوکت
class SockReader {
  final Socket sock;
  final List<Uint8List> _chunks = [];
  int _off = 0, _buffered = 0;
  bool _closed = false;
  Completer<void>? _wait;
  late final StreamSubscription<Uint8List> _sub;

  SockReader(this.sock) {
    _sub = sock.listen((d) {
      _chunks.add(d);
      _buffered += d.length;
      if (_buffered > 4 * 1024 * 1024 && !_sub.isPaused) _sub.pause();
      _wake();
    }, onDone: () {
      _closed = true;
      _wake();
    }, onError: (_) {
      _closed = true;
      _wake();
    }, cancelOnError: true);
  }

  void _wake() {
    final w = _wait;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List> readSome(int max, {Duration timeout = const Duration(seconds: 30)}) async {
    while (_chunks.isEmpty) {
      if (_closed) throw const SocketException('connection closed');
      _wait = Completer<void>();
      await _wait!.future.timeout(timeout);
    }
    final c = _chunks.first;
    final take = min(c.length - _off, max);
    final out = Uint8List.sublistView(c, _off, _off + take);
    _off += take;
    _buffered -= take;
    if (_off >= c.length) {
      _chunks.removeAt(0);
      _off = 0;
    }
    if (_buffered < 1024 * 1024 && _sub.isPaused) _sub.resume();
    return out;
  }

  Future<Uint8List> readExact(int n, {Duration timeout = const Duration(seconds: 30)}) async {
    final bb = BytesBuilder(copy: true);
    var got = 0;
    while (got < n) {
      final c = await readSome(n - got, timeout: timeout);
      bb.add(c);
      got += c.length;
    }
    return bb.takeBytes();
  }

  Future<Map<String, dynamic>> readMsg({Duration timeout = const Duration(seconds: 30)}) async {
    final h = await readExact(4, timeout: timeout);
    final len = ByteData.sublistView(h).getUint32(0, Endian.big);
    if (len > 1024 * 1024) throw const FormatException('bad message');
    final body = await readExact(len, timeout: timeout);
    return json.decode(utf8.decode(body)) as Map<String, dynamic>;
  }

  void dispose() {
    _sub.cancel();
  }
}

Future<void> writeMsg(Socket s, Map<String, dynamic> m) async {
  final b = utf8.encode(json.encode(m));
  final h = ByteData(4)..setUint32(0, b.length, Endian.big);
  s.add(h.buffer.asUint8List());
  s.add(b);
  await s.flush();
}

// ---------------------------------------------------------------- وضعیت برنامه
class AppState extends ChangeNotifier {
  late SharedPreferences prefs;
  String lang = 'fa';
  int port = 50505;
  String deviceName = 'Android-Phone';
  String manualIp = '';
  String myIp = '127.0.0.1';
  String recvDir = '/storage/emulated/0/Download/FileShare';

  List<Entry> history = [];
  List<Fav> favs = [];
  List<SendItem> files = [];
  List<TNode> sendRoots = [];
  final Map<String, bool> sendSelected = {};
  Map<String, String> devices = {};
  String? pendingIp;

  bool receiveMode = false;
  bool sending = false;
  String status = '';
  String totalText = '';
  String sendText = '';
  double sendPct = 0;
  String recvText = '';
  double recvPct = 0;
  int _lastSendInt = -1, _lastRecvInt = -1;
  int _totalGen = 0;

  ServerSocket? _server;
  final Map<String, bool> _batches = {};
  final Map<String, int> _batchGot = {};
  final Map<String, List<String>> _batchPaths = {};

  String t(String k) => T[lang]?[k] ?? k;

  void setStatus(String s) {
    status = s;
    notifyListeners();
  }

  void toast(String s) => msgKey.currentState?.showSnackBar(SnackBar(content: Text(s)));

  void refresh() => notifyListeners();

  Future<void> init() async {
    status = t('ready');
    prefs = await SharedPreferences.getInstance();
    try {
      final s = prefs.getString('settings');
      if (s != null) {
        final m = json.decode(s) as Map<String, dynamic>;
        lang = (m['lang'] ?? 'fa').toString();
        if (!T.containsKey(lang)) lang = 'fa';
        port = (m['port'] ?? 50505) as int;
        deviceName = (m['name'] ?? deviceName).toString();
        manualIp = (m['ip'] ?? '').toString();
        recvDir = (m['recvDir'] ?? recvDir).toString();
      }
    } catch (_) {}
    try {
      final h = prefs.getString('history');
      if (h != null) {
        history = (json.decode(h) as List).map((e) => Entry.fromJson(Map<String, dynamic>.from(e))).toList();
      }
    } catch (_) {}
    try {
      final f = prefs.getString('favs');
      if (f != null) {
        favs = (json.decode(f) as List).map((e) => Fav(e['name'].toString(), e['ip'].toString())).toList();
      }
    } catch (_) {}
    status = t('ready');
    myIp = manualIp.isNotEmpty ? manualIp : await detectIp();
    await startServer();
  }

  Future<String> detectIp() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      String? best;
      for (final i in ifs) {
        final n = i.name.toLowerCase();
        for (final a in i.addresses) {
          if (n.startsWith('wlan') || n.startsWith('ap') || n.startsWith('eth') || n.contains('wifi')) {
            return a.address;
          }
          best ??= a.address;
        }
      }
      return best ?? '127.0.0.1';
    } catch (_) {
      return '127.0.0.1';
    }
  }

  Future<void> saveSettings() async {
    await prefs.setString('settings', json.encode({
      'lang': lang, 'port': port, 'name': deviceName, 'ip': manualIp, 'recvDir': recvDir
    }));
  }

  Future<void> saveHistory() async {
    if (history.length > 2000) history = history.sublist(history.length - 2000);
    await prefs.setString('history', json.encode(history.map((e) => e.toJson()).toList()));
  }

  Future<void> saveFavs() async {
    await prefs.setString('favs', json.encode(favs.map((f) => {'name': f.name, 'ip': f.ip}).toList()));
  }

  Future<void> applySettings(
      {required String newLang, required String newDir, required int newPort,
      required String ip, required String name}) async {
    final portChanged = newPort != port;
    lang = newLang;
    recvDir = newDir.isEmpty ? recvDir : newDir;
    port = newPort;
    manualIp = ip;
    deviceName = name.isEmpty ? deviceName : name;
    myIp = manualIp.isNotEmpty ? manualIp : await detectIp();
    await saveSettings();
    await ensureRecvDir();
    if (portChanged) await startServer();
    notifyListeners();
  }

  // ----- دسترسی‌ها -----
  Future<bool> ensureStorage() async {
    try {
      if (await Permission.manageExternalStorage.isGranted) return true;
      var s = await Permission.manageExternalStorage.request();
      if (s.isGranted) return true;
      s = await Permission.storage.request();
      return s.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureRecvDir() async {
    try {
      await Directory(recvDir).create(recursive: true);
    } catch (_) {
      try {
        final d = await getExternalStorageDirectory();
        if (d != null) {
          recvDir = '${d.path}/FileShare';
          await Directory(recvDir).create(recursive: true);
        }
      } catch (_) {}
    }
  }

  void _updateWake() {
    try {
      if (receiveMode || sending) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (_) {}
  }

  void setReceiveMode(bool on) {
    if (on == receiveMode) return;
    receiveMode = on;
    _updateWake();
    notifyListeners();
  }

  // ----- سرور (گیرنده) -----
  Future<void> startServer() async {
    await stopServer();
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
      _server!.listen(_handle, onError: (_) {});
    } catch (e) {
      status = 'Port $port: $e';
    }
  }

  Future<void> stopServer() async {
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
  }

  Future<String> safeDest(String rel) async {
    final parts = rel
        .split(RegExp(r'[\\/]+'))
        .where((p) => p.isNotEmpty && p != '.' && p != '..')
        .map((p) => p.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_'))
        .toList();
    if (parts.isEmpty) parts.add('file');
    final folder = [recvDir, ...parts.take(parts.length - 1)].join('/');
    await Directory(folder).create(recursive: true);
    return uniquePath(folder, parts.last);
  }

  Future<bool> askUser(String text) async {
    final ctx = navKey.currentContext;
    if (ctx == null) return false;
    final c = Completer<bool>();
    BuildContext? dlg;
    showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dctx) {
        dlg = dctx;
        return AlertDialog(
          title: Text(t('ask_title')),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t('reject'))),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: Text(t('accept'))),
          ],
        );
      },
    ).then((v) {
      if (!c.isCompleted) c.complete(v ?? false);
    });
    return c.future.timeout(const Duration(seconds: 90), onTimeout: () {
      final d = dlg;
      if (d != null && d.mounted) Navigator.pop(d, false);
      return false;
    });
  }

  Future<void> _handle(Socket c) async {
    final r = SockReader(c);
    final ip = c.remoteAddress.address;
    try {
      final m = await r.readMsg();
      if (!receiveMode) {
        if (m['type'] == 'file') await writeMsg(c, {'ok': false, 'reason': 'not_receiving'});
        return;
      }
      if (m['type'] == 'hello') {
        await writeMsg(c, {'name': deviceName});
        return;
      }
      final rel = (m['name'] ?? 'file').toString();
      final size = (m['size'] as num).toInt();
      final sender = (m['from'] ?? ip).toString();
      final count = ((m['count'] ?? 1) as num).toInt();
      final total = ((m['total'] ?? size) as num).toInt();
      final key = '$ip|${m['batch'] ?? ''}';
      final peer = '$sender ($ip)';

      if (!_batches.containsKey(key)) {
        final ok = await askUser(fmt(t('ask_text'),
            {'sender': sender, 'ip': ip, 'count': count, 'total': human(total), 'name': rel}));
        _batches[key] = ok;
        _batchGot[key] = 0;
        _batchPaths[key] = [];
        if (!ok) addHistory(newEntry(rel, 'recv', peer, '', 'rej'));
      }
      if (_batches[key] != true) {
        await writeMsg(c, {'ok': false, 'reason': 'rejected'});
        return;
      }

      final path = await safeDest(rel);
      await writeMsg(c, {'ok': true});
      final out = File(path).openWrite();
      var got = 0;
      try {
        while (got < size) {
          final chunk = await r.readSome(min(kChunk, size - got));
          out.add(chunk);
          got += chunk.length;
          _setRecvProgress(fmt(t('receiving'), {'s': sender, 'name': rel}), got * 100 / max(size, 1));
        }
        await out.flush();
      } finally {
        await out.close();
      }
      await writeMsg(c, {'done': true});
      addHistory(newEntry(rel, 'recv', peer, path, 'ok'));
      setStatus(fmt(t('recv_ok'), {'name': rel}));
      _batchGot[key] = (_batchGot[key] ?? 0) + 1;
      _batchPaths[key]!.add(path);
      if (_batchGot[key]! >= count) showReceived(List<String>.from(_batchPaths[key]!), sender);
    } catch (e) {
      setStatus(fmt(t('recv_err'), {'e': e}));
    } finally {
      r.dispose();
      c.destroy();
    }
  }

  void _setRecvProgress(String text, double pct) {
    recvText = text;
    recvPct = pct;
    if (pct.floor() != _lastRecvInt) {
      _lastRecvInt = pct.floor();
      notifyListeners();
    }
  }

  void _setSendProgress(String text, double pct) {
    sendText = text;
    sendPct = pct;
    if (pct.floor() != _lastSendInt) {
      _lastSendInt = pct.floor();
      notifyListeners();
    }
  }

  Entry newEntry(String file, String dir, String peer, String path, String status) {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return Entry(
      id: n.microsecondsSinceEpoch.toString(),
      time: '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}:${two(n.second)}',
      file: file, dir: dir, peer: peer, path: path, status: status,
    );
  }

  void addHistory(Entry e) {
    history.add(e);
    saveHistory();
    notifyListeners();
  }

  // ----- اسکن شبکه -----
  Future<void> scan() async {
    devices = {};
    setStatus(t('scanning'));
    final prefix = myIp.split('.').take(3).join('.');
    final ips = <String>[for (var i = 1; i < 255; i++) '$prefix.$i']..remove(myIp);
    for (var i = 0; i < ips.length; i += 50) {
      await Future.wait(ips.skip(i).take(50).map(_probe));
    }
    setStatus(t('scan_done'));
  }

  Future<void> _probe(String ip) async {
    Socket? s;
    SockReader? r;
    try {
      s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 600));
      r = SockReader(s);
      await writeMsg(s, {'type': 'hello'});
      final m = await r.readMsg(timeout: const Duration(seconds: 2));
      devices[ip] = (m['name'] ?? '?').toString();
      notifyListeners();
    } catch (_) {
    } finally {
      r?.dispose();
      s?.destroy();
    }
  }

  // ----- لیست ارسال -----
  void addItem(String path, bool isDir) {
    final p = _norm(path);
    for (final f in files) {
      if (f.path == p || isUnder(p, f.path)) return;
    }
    if (isDir) files.removeWhere((f) => isUnder(f.path, p));
    files.add(SendItem(p, isDir));
  }

  void syncSendRoots() {
    final old = {for (final n in sendRoots) n.path: n};
    sendRoots = files.map((f) {
      final o = old[f.path];
      if (o != null) return o;
      var size = '';
      if (!f.isDir) {
        try {
          size = human(File(f.path).lengthSync());
        } catch (_) {
          size = '?';
        }
      }
      final name = f.path.split('/').where((s) => s.isNotEmpty).isEmpty
          ? f.path
          : f.path.split('/').where((s) => s.isNotEmpty).last;
      return TNode(name, f.path, f.isDir, 0, size: size);
    }).toList();
    sendSelected.removeWhere((k, v) => !files.any((f) => f.path == k));
    notifyListeners();
  }

  void removeSelected() {
    if (sendSelected.isEmpty) return;
    final sel = Set<String>.from(sendSelected.keys);
    files.removeWhere((f) => sel.contains(f.path));
    sendSelected.clear();
    syncSendRoots();
    refreshTotal();
  }

  Future<void> refreshTotal() async {
    final gen = ++_totalGen;
    final items = List<SendItem>.of(files);
    totalText = fmt(t('count_wait'), {'items': items.length});
    notifyListeners();
    var nf = 0, size = 0;
    for (final it in items) {
      if (it.isDir) {
        try {
          await for (final e in Directory(it.path).list(recursive: true, followLinks: false).handleError((_) {})) {
            if (e is File) {
              nf++;
              try {
                size += await e.length();
              } catch (_) {}
            }
          }
        } catch (_) {}
      } else {
        try {
          final f = File(it.path);
          if (await f.exists()) {
            nf++;
            size += await f.length();
          }
        } catch (_) {}
      }
      if (gen != _totalGen) return;
    }
    totalText = fmt(t('count'), {'items': items.length, 'files': nf, 'size': human(size)});
    notifyListeners();
  }

  Future<List<Pair>> expandItems(List<SendItem> items) async {
    final out = <Pair>[];
    for (final it in items) {
      if (it.isDir) {
        final parts = it.path.split('/').where((s) => s.isNotEmpty).toList();
        final base = parts.isEmpty ? 'root' : parts.last;
        try {
          await for (final e in Directory(it.path).list(recursive: true, followLinks: false).handleError((_) {})) {
            if (e is File) {
              final rel = e.path.substring(it.path.length).replaceAll(RegExp(r'^/+'), '');
              out.add(Pair(e.path, '$base/$rel'));
            }
          }
        } catch (_) {}
      } else if (await File(it.path).exists()) {
        out.add(Pair(it.path, it.path.split('/').last));
      }
    }
    return out;
  }

  // ----- ارسال -----
  Future<void> sendAll(String ip) async {
    if (ip.isEmpty) {
      toast(t('w_no_recv'));
      return;
    }
    if (files.isEmpty) {
      toast(t('w_no_files'));
      return;
    }
    if (sending) return;
    sending = true;
    _updateWake();
    notifyListeners();
    try {
      final list = await expandItems(List<SendItem>.of(files));
      if (list.isEmpty) {
        toast(t('w_no_files'));
        return;
      }
      var total = 0;
      for (final p in list) {
        try {
          total += await File(p.path).length();
        } catch (_) {}
      }
      var doneAll = 0;
      final peer = '${devices[ip] ?? ip} ($ip)';
      final batch = '${DateTime.now().microsecondsSinceEpoch}';
      for (var idx = 0; idx < list.length; idx++) {
        final p = list[idx];
        final rel = p.rel.replaceAll('\\', '/');
        var st = 'fail';
        Socket? s;
        SockReader? r;
        try {
          final size = await File(p.path).length();
          s = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
          r = SockReader(s);
          await writeMsg(s, {
            'type': 'file', 'name': rel, 'size': size, 'from': deviceName,
            'batch': batch, 'count': list.length, 'total': total
          });
          final reply = await r.readMsg(timeout: const Duration(seconds: 120));
          if (reply['ok'] != true) {
            if (reply['reason'] == 'not_receiving') {
              setStatus(t('not_receiving'));
              addHistory(newEntry(rel, 'send', peer, p.path, 'fail'));
            } else {
              setStatus(t('rejected'));
              addHistory(newEntry(rel, 'send', peer, p.path, 'rej'));
            }
            break;
          }
          var sent = 0;
          await for (final chunk in File(p.path).openRead()) {
            s.add(chunk);
            sent += chunk.length;
            await s.flush();
            _setSendProgress(fmt(t('sending'), {'i': idx + 1, 'n': list.length, 'name': rel}),
                (doneAll + sent) * 100 / max(total, 1));
          }
          await r.readMsg(timeout: const Duration(seconds: 30));
          st = 'ok';
          doneAll += size;
        } catch (e) {
          setStatus(fmt(t('send_err'), {'name': rel, 'e': e}));
        } finally {
          r?.dispose();
          s?.destroy();
        }
        addHistory(newEntry(rel, 'send', peer, p.path, st));
      }
      _setSendProgress(t('send_done'), 100);
    } finally {
      sending = false;
      _updateWake();
      notifyListeners();
    }
  }

  // ----- تاریخچه -----
  void deleteEntries(List<Entry> es) {
    final ids = es.map((e) => e.id).toSet();
    history.removeWhere((h) => ids.contains(h.id));
    saveHistory();
    notifyListeners();
  }

  Future<void> deleteFromDisk(List<Entry> es) async {
    final ex = es.where((e) => e.path.isNotEmpty && File(e.path).existsSync()).toList();
    if (ex.isEmpty) {
      toast(t('no_file'));
      return;
    }
    if (!await confirm(fmt(t('confirm_disk'), {'n': ex.length}))) return;
    for (final e in ex) {
      try {
        await File(e.path).delete();
      } catch (_) {}
    }
    deleteEntries(es);
  }

  Future<void> clearHistory() async {
    if (!await confirm(t('confirm_clear'))) return;
    history.clear();
    saveHistory();
    notifyListeners();
  }

  Future<void> openPath(String path) async {
    if (path.isNotEmpty && File(path).existsSync()) {
      await OpenFilex.open(path);
    } else {
      toast(t('no_file'));
    }
  }

  // ----- مخاطبین -----
  bool addFav(String name, String ip) {
    if (favs.any((f) => f.ip == ip)) {
      toast(t('w_dup'));
      return false;
    }
    favs.add(Fav(name, ip));
    saveFavs();
    notifyListeners();
    return true;
  }

  void renameFav(Fav f, String name) {
    f.name = name;
    saveFavs();
    notifyListeners();
  }

  void deleteFav(Fav f) {
    favs.remove(f);
    saveFavs();
    notifyListeners();
  }

  // ----- دیالوگ‌ها -----
  void copyText(String s) {
    Clipboard.setData(ClipboardData(text: s));
    toast(t('copied'));
  }

  Future<bool> confirm(String text) async {
    final ctx = navKey.currentContext;
    if (ctx == null) return false;
    final r = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('no'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('yes'))),
        ],
      ),
    );
    return r ?? false;
  }

  Future<String?> askText(String title, String label, {String initial = ''}) async {
    final ctx = navKey.currentContext;
    if (ctx == null) return null;
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(t('save'))),
        ],
      ),
    );
  }

  void showLocation(String path) {
    final ctx = navKey.currentContext;
    if (ctx == null) return;
    final dir = FileSystemEntity.isDirectorySync(path) ? path : File(path).parent.path;
    showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Text(t('location')),
        content: SelectableText(dir),
        actions: [
          TextButton(onPressed: () => copyText(dir), child: Text(t('copy'))),
          TextButton(onPressed: () => Navigator.pop(d), child: Text(t('close'))),
        ],
      ),
    );
  }

  void showReceived(List<String> paths, String peer) {
    final ctx = navKey.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Text(t('got_title')),
        content: Text(fmt(t('got_text'), {'n': paths.length, 'peer': peer}) +
            (paths.length == 1 ? '\n\n${paths.first.split('/').last}' : '')),
        actions: [
          if (paths.length == 1)
            TextButton(
                onPressed: () {
                  Navigator.pop(d);
                  openPath(paths.first);
                },
                child: Text(t('open_file'))),
          TextButton(
              onPressed: () {
                Navigator.pop(d);
                showLocation(paths.first);
              },
              child: Text(t('open_folder'))),
          TextButton(onPressed: () => Navigator.pop(d), child: Text(t('close'))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- ویجت‌های کمکی
class RBtn extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback? onTap;
  const RBtn(this.text, this.color, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}

class SquareCheck extends StatelessWidget {
  final bool checked;
  final VoidCallback onTap;
  const SquareCheck({super.key, required this.checked, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: checked ? kRed : kGreen,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: checked ? const Color(0xFFEF9A9A) : const Color(0xFFA5D6A7), width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 2))],
            ),
            child: checked ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
          ),
        ),
      );
}

class Act {
  final String label;
  final IconData icon;
  final VoidCallback fn;
  Act(this.label, this.icon, this.fn);
}

void actionSheet(BuildContext ctx, String title, List<Act> acts) {
  showModalBottomSheet(
    context: ctx,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          for (final a in acts)
            ListTile(
                leading: Icon(a.icon),
                title: Text(a.label),
                onTap: () {
                  Navigator.pop(c);
                  a.fn();
                }),
        ]),
      ),
    ),
  );
}

/// لیست با اسلایدر (Scrollbar)
class SBList extends StatefulWidget {
  final List<Widget>? children;
  final int? count;
  final IndexedWidgetBuilder? builder;
  const SBList({super.key, this.children, this.count, this.builder});
  @override
  State<SBList> createState() => _SBListState();
}

class _SBListState extends State<SBList> {
  final sc = ScrollController();
  @override
  void dispose() {
    sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: sc,
        thumbVisibility: true,
        interactive: true,
        child: widget.children != null
            ? ListView(controller: sc, children: widget.children!)
            : ListView.builder(controller: sc, itemCount: widget.count, itemBuilder: widget.builder!),
      );
}

// ---------------------------------------------------------------- لیست درختی با مربع انتخاب
class CheckTree extends StatefulWidget {
  final List<TNode> roots;
  final bool nestedChecks;
  final Map<String, bool> selected;
  final VoidCallback onChanged;
  final void Function(TNode)? onMenu;
  final void Function(TNode)? onOpenFile;
  const CheckTree({
    super.key,
    required this.roots,
    required this.nestedChecks,
    required this.selected,
    required this.onChanged,
    this.onMenu,
    this.onOpenFile,
  });
  @override
  State<CheckTree> createState() => CheckTreeState();
}

class CheckTreeState extends State<CheckTree> {
  final sc = ScrollController();

  @override
  void dispose() {
    sc.dispose();
    super.dispose();
  }

  List<TNode> _visible() {
    final out = <TNode>[];
    void walk(TNode n) {
      out.add(n);
      if (n.isDir && n.expanded) {
        for (final k in n.kids) {
          walk(k);
        }
      }
    }

    for (final r in widget.roots) {
      walk(r);
    }
    return out;
  }

  Future<void> _load(TNode n) async {
    final dirs = <TNode>[], fl = <TNode>[];
    try {
      await for (final e in Directory(n.path).list(followLinks: false).handleError((_) {})) {
        final name = e.path.split('/').last;
        if (e is Directory) {
          dirs.add(TNode(name, e.path, true, n.depth + 1));
        } else if (e is File) {
          var sz = 0;
          try {
            sz = e.lengthSync();
          } catch (_) {}
          fl.add(TNode(name, e.path, false, n.depth + 1, size: human(sz)));
        }
      }
    } catch (_) {}
    dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    fl.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    n.kids = [...dirs, ...fl].take(6000).toList();
    n.loaded = true;
  }

  Future<void> toggleExpand(TNode n) async {
    if (!n.isDir) return;
    if (!n.expanded && !n.loaded) await _load(n);
    if (!mounted) return;
    setState(() => n.expanded = !n.expanded);
  }

  void toggleSelect(TNode n) {
    if (widget.selected.containsKey(n.path)) {
      widget.selected.remove(n.path);
    } else {
      widget.selected[n.path] = n.isDir;
    }
    setState(() {});
    widget.onChanged();
  }

  void selectAll() {
    for (final n in _visible()) {
      if (n.depth == 0 || widget.nestedChecks) widget.selected[n.path] = n.isDir;
    }
    setState(() {});
    widget.onChanged();
  }

  void deselectAll() {
    widget.selected.clear();
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final vis = _visible();
    return Scrollbar(
      controller: sc,
      thumbVisibility: true,
      interactive: true,
      child: ListView.builder(
        controller: sc,
        itemCount: vis.length,
        itemExtent: 46,
        itemBuilder: (c, i) {
          final n = vis[i];
          final sel = widget.selected.containsKey(n.path);
          final hasCheck = n.depth == 0 || widget.nestedChecks;
          return InkWell(
            onTap: () {
              if (n.isDir) {
                toggleExpand(n);
              } else {
                widget.onOpenFile?.call(n);
              }
            },
            onLongPress: () => widget.onMenu?.call(n),
            child: Container(
              color: sel ? const Color(0xFFE8F1FB) : (i.isEven ? Colors.white : const Color(0xFFF3F7FC)),
              child: Row(children: [
                const SizedBox(width: 4),
                hasCheck ? SquareCheck(checked: sel, onTap: () => toggleSelect(n)) : const SizedBox(width: 38),
                SizedBox(width: n.depth * 18.0),
                SizedBox(
                    width: 22,
                    child: n.isDir
                        ? Icon(n.expanded ? Icons.expand_more : Icons.chevron_right, size: 22, color: kGray)
                        : null),
                Icon(n.isDir ? Icons.folder : Icons.insert_drive_file, size: 20, color: n.isDir ? kOrange : kGray),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(n.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: n.isDir ? FontWeight.bold : FontWeight.normal))),
                if (n.size.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(n.size, style: const TextStyle(fontSize: 12, color: kGray))),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- صفحه انتخاب فایل
class BrowsePage extends StatefulWidget {
  final AppState st;
  const BrowsePage({super.key, required this.st});
  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final selected = <String, bool>{};
  final treeKey = GlobalKey<CheckTreeState>();
  List<TNode> roots = [];
  AppState get st => widget.st;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    if (!await st.ensureStorage()) st.toast(st.t('perm_needed'));
    final r = <TNode>[];
    final internal = Directory('/storage/emulated/0');
    if (await internal.exists()) r.add(TNode(st.t('internal'), internal.path, true, 0));
    try {
      await for (final e in Directory('/storage').list().handleError((_) {})) {
        final n = e.path.split('/').last;
        if (e is Directory && n != 'emulated' && n != 'self') r.add(TNode(n, e.path, true, 0));
      }
    } catch (_) {}
    if (r.isEmpty) r.add(TNode('/', '/', true, 0));
    if (mounted) setState(() => roots = r);
  }

  void _menu(TNode n) {
    final tk = treeKey.currentState;
    if (tk == null) return;
    actionSheet(context, n.name, [
      Act(st.t('m_toggle'), Icons.check_box, () => tk.toggleSelect(n)),
      if (n.isDir) Act(st.t('m_expand'), Icons.folder_open, () => tk.toggleExpand(n)),
      Act(st.t('m_select_all'), Icons.select_all, tk.selectAll),
      Act(st.t('m_deselect'), Icons.deselect, tk.deselectAll),
      Act(st.t('m_copy'), Icons.copy, () => st.copyText(n.path)),
    ]);
  }

  void _add() {
    for (final e in selected.entries) {
      st.addItem(e.key, e.value);
    }
    st.syncSendRoots();
    st.refreshTotal();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBorder,
        appBar: AppBar(backgroundColor: kBorder, title: Text(st.t('b_title'))),
        body: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(5, 0, 5, 5),
            color: kBg,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(st.t('b_hint'), style: const TextStyle(color: kGray, fontSize: 12))),
              Expanded(
                  child: CheckTree(
                key: treeKey,
                roots: roots,
                nestedChecks: true,
                selected: selected,
                onChanged: () => setState(() {}),
                onMenu: _menu,
              )),
              Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(fmt(st.t('b_selected'), {'n': selected.length}),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: kBlue))),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  RBtn(st.t('b_sel_all'), kOrange, () => treeKey.currentState?.selectAll()),
                  RBtn(st.t('b_desel'), kGray, () => treeKey.currentState?.deselectAll()),
                  RBtn(st.t('b_add'), kGreen, _add),
                ]),
              ),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------- تب ارسال
class SendTab extends StatefulWidget {
  final AppState st;
  const SendTab({super.key, required this.st});
  @override
  State<SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<SendTab> {
  final ipCtrl = TextEditingController();
  final treeKey = GlobalKey<CheckTreeState>();
  AppState get st => widget.st;

  @override
  void dispose() {
    ipCtrl.dispose();
    super.dispose();
  }

  void _menu(TNode n) {
    final tk = treeKey.currentState;
    if (tk == null) return;
    actionSheet(context, n.name, [
      if (n.depth == 0)
        Act(st.t('m_remove'), Icons.delete, () {
          if (st.sendSelected.isEmpty) st.sendSelected[n.path] = n.isDir;
          st.removeSelected();
        }),
      Act(st.t('m_select_all'), Icons.select_all, tk.selectAll),
      Act(st.t('m_deselect'), Icons.deselect, tk.deselectAll),
      if (n.isDir)
        Act(st.t('m_expand'), Icons.folder_open, () => tk.toggleExpand(n))
      else
        Act(st.t('m_open'), Icons.open_in_new, () => st.openPath(n.path)),
      Act(st.t('m_reveal'), Icons.folder, () => st.showLocation(n.path)),
      Act(st.t('m_copy'), Icons.copy, () => st.copyText(n.path)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (st.pendingIp != null) {
      ipCtrl.text = st.pendingIp!;
      st.pendingIp = null;
    }
    final devs = st.devices.entries.toList();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(st.t('receiver'), style: const TextStyle(fontWeight: FontWeight.bold, color: kBlue)),
              const SizedBox(height: 6),
              Row(children: [
                RBtn(st.t('scan'), kBlue, () => st.scan()),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                  controller: ipCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: st.t('manual_ip'), isDense: true, border: const OutlineInputBorder()),
                )),
              ]),
              SizedBox(
                height: 96,
                child: devs.isEmpty
                    ? const SizedBox()
                    : SBList(
                        count: devs.length,
                        builder: (c, i) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.devices, color: kBlue),
                          title: Text(devs[i].value),
                          subtitle: Text(devs[i].key),
                          onTap: () => ipCtrl.text = devs[i].key,
                          onLongPress: () => actionSheet(context, devs[i].value, [
                            Act(st.t('m_use'), Icons.send, () => ipCtrl.text = devs[i].key),
                            Act(st.t('add_fav'), Icons.star, () async {
                              final n = await st.askText(st.t('fav_name'), st.t('fav_name'), initial: devs[i].value);
                              if (n != null && n.isNotEmpty) st.addFav(n, devs[i].key);
                            }),
                            Act(st.t('m_copy_ip'), Icons.copy, () => st.copyText(devs[i].key)),
                          ]),
                        ),
                      ),
              ),
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: RBtn(st.t('add_fav'), kOrange, () async {
                    final ip = ipCtrl.text.trim();
                    if (ip.isEmpty) {
                      st.toast(st.t('w_pick_ip'));
                      return;
                    }
                    final n = await st.askText(st.t('fav_name'), st.t('fav_name'), initial: st.devices[ip] ?? ip);
                    if (n != null && n.isNotEmpty) st.addFav(n, ip);
                  })),
            ]),
          ),
        ),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(st.t('files_box'), style: const TextStyle(fontWeight: FontWeight.bold, color: kBlue)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  RBtn(st.t('add_files'), kPurple, () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => BrowsePage(st: st)));
                  }),
                  RBtn(st.t('remove_sel'), kRed, st.removeSelected),
                ]),
                const SizedBox(height: 6),
                Expanded(
                    child: Container(
                  decoration: BoxDecoration(border: Border.all(color: kBorder)),
                  child: CheckTree(
                    key: treeKey,
                    roots: st.sendRoots,
                    nestedChecks: false,
                    selected: st.sendSelected,
                    onChanged: () => setState(() {}),
                    onMenu: _menu,
                    onOpenFile: (n) => st.openPath(n.path),
                  ),
                )),
                Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(st.totalText)),
                RBtn(st.sending ? '...' : st.t('send'), kGreen, st.sending ? null : () => st.sendAll(ipCtrl.text.trim())),
                const SizedBox(height: 6),
                ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: st.sendPct / 100, minHeight: 10)),
                Text('${st.sendText}  ${st.sendPct.floor()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: kBlue), textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- لیست درختی تاریخچه/دریافت
class _DirNode {
  final String name;
  final Map<String, _DirNode> dirs = {};
  final List<MapEntry<String, Entry>> leaves = [];
  _DirNode(this.name);
}

List<Entry> _collect(_DirNode n) {
  final out = <Entry>[for (final l in n.leaves) l.value];
  for (final d in n.dirs.values) {
    out.addAll(_collect(d));
  }
  return out;
}

class EntryTree extends StatelessWidget {
  final AppState st;
  final List<Entry> entries;
  const EntryTree({super.key, required this.st, required this.entries});

  void _menu(BuildContext ctx, String title, List<Entry> es) {
    final first = es.isNotEmpty ? es.first : null;
    actionSheet(ctx, title, [
      if (es.length == 1 && first != null) Act(st.t('m_open'), Icons.open_in_new, () => st.openPath(first.path)),
      if (first != null && first.path.isNotEmpty)
        Act(st.t('m_reveal'), Icons.folder, () => st.showLocation(first.path)),
      Act(st.t('m_copy'), Icons.copy,
          () => st.copyText(es.map((e) => e.path.isNotEmpty ? e.path : e.file).join('\n'))),
      Act(st.t('m_delete_list'), Icons.delete_outline, () => st.deleteEntries(es)),
      Act(st.t('m_delete_disk'), Icons.delete_forever, () => st.deleteFromDisk(es)),
    ]);
  }

  List<Widget> _render(BuildContext ctx, _DirNode n, String prefix) {
    final out = <Widget>[];
    for (final d in n.dirs.values) {
      final key = '$prefix/${d.name}';
      out.add(GestureDetector(
        onLongPress: () => _menu(ctx, d.name, _collect(d)),
        child: ExpansionTile(
          key: PageStorageKey('d:$key'),
          leading: const Icon(Icons.folder, color: kOrange),
          title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          childrenPadding: const EdgeInsetsDirectional.only(start: 14),
          children: _render(ctx, d, key),
        ),
      ));
    }
    for (final l in n.leaves) {
      final e = l.value;
      final s = {'ok': st.t('st_ok'), 'fail': st.t('st_fail'), 'rej': st.t('st_rej')}[e.status] ?? e.status;
      final d = {'send': st.t('dir_send'), 'recv': st.t('dir_recv')}[e.dir] ?? e.dir;
      out.add(ListTile(
        dense: true,
        leading: Icon(Icons.insert_drive_file, color: e.status == 'ok' ? kGreen : kRed),
        title: Text(l.key, overflow: TextOverflow.ellipsis),
        subtitle: Text('${e.time}  •  $d  •  ${e.peer}  •  $s', style: const TextStyle(fontSize: 11)),
        onTap: () => st.openPath(e.path),
        onLongPress: () => _menu(ctx, l.key, [e]),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final root = _DirNode('');
    for (final e in entries.reversed) {
      final parts = e.file.split(RegExp(r'[\\/]+')).where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) parts.add(e.file);
      var node = root;
      for (var i = 0; i < parts.length - 1; i++) {
        node = node.dirs.putIfAbsent(parts[i], () => _DirNode(parts[i]));
      }
      node.leaves.add(MapEntry(parts.last, e));
    }
    final kids = _render(context, root, '');
    if (kids.isEmpty) return Center(child: Text(st.t('empty'), style: const TextStyle(color: kGray)));
    return SBList(children: kids);
  }
}

// ---------------------------------------------------------------- تب دریافت
class RecvTab extends StatelessWidget {
  final AppState st;
  const RecvTab({super.key, required this.st});
  @override
  Widget build(BuildContext context) {
    final on = st.receiveMode;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          on ? fmt(st.t('r_on'), {'ip': st.myIp, 'port': st.port}) : st.t('r_off'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: on ? kGreen : kRed),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          RBtn(on ? st.t('r_stop') : st.t('r_start'), on ? kRed : kGreen, () => st.setReceiveMode(!on)),
          RBtn(st.t('recv_folder'), kPurple, () => st.showLocation(st.recvDir)),
        ]),
        const SizedBox(height: 8),
        Expanded(
            child: Container(
          decoration: BoxDecoration(border: Border.all(color: kBorder), color: Colors.white),
          child: EntryTree(st: st, entries: st.history.where((e) => e.dir == 'recv').toList()),
        )),
        const SizedBox(height: 6),
        ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: st.recvPct / 100, minHeight: 10)),
        Text('${st.recvText}  ${st.recvPct.floor()}%',
            style: const TextStyle(fontWeight: FontWeight.bold, color: kBlue), textAlign: TextAlign.center),
      ]),
    );
  }
}

// ---------------------------------------------------------------- تب تاریخچه
class HistTab extends StatelessWidget {
  final AppState st;
  const HistTab({super.key, required this.st});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(alignment: AlignmentDirectional.centerStart, child: RBtn(st.t('h_clear'), kRed, st.clearHistory)),
          const SizedBox(height: 8),
          Expanded(
              child: Container(
            decoration: BoxDecoration(border: Border.all(color: kBorder), color: Colors.white),
            child: EntryTree(st: st, entries: st.history),
          )),
        ]),
      );
}

// ---------------------------------------------------------------- تب مخاطبین پرکاربرد
class FavTab extends StatelessWidget {
  final AppState st;
  final void Function(Fav) onUse;
  const FavTab({super.key, required this.st, required this.onUse});

  Future<void> _rename(Fav f) async {
    final n = await st.askText(st.t('f_rename'), st.t('fav_new'), initial: f.name);
    if (n != null && n.isNotEmpty) st.renameFav(f, n);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
              alignment: AlignmentDirectional.centerStart,
              child: RBtn(st.t('f_add'), kGreen, () async {
                final n = await st.askText(st.t('fav_name'), st.t('fav_name'));
                if (n == null || n.isEmpty) return;
                final ip = await st.askText(st.t('fav_ip'), st.t('fav_ip'));
                if (ip != null && ip.isNotEmpty) st.addFav(n, ip);
              })),
          const SizedBox(height: 8),
          Expanded(
              child: Container(
            decoration: BoxDecoration(border: Border.all(color: kBorder), color: Colors.white),
            child: st.favs.isEmpty
                ? Center(child: Text(st.t('empty'), style: const TextStyle(color: kGray)))
                : SBList(
                    count: st.favs.length,
                    builder: (c, i) {
                      final f = st.favs[i];
                      return ListTile(
                        leading: const Icon(Icons.star, color: kOrange),
                        title: Text(f.name),
                        subtitle: Text(f.ip),
                        onTap: () => onUse(f),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'use') onUse(f);
                            if (v == 'rename') _rename(f);
                            if (v == 'copy') st.copyText(f.ip);
                            if (v == 'del') st.deleteFav(f);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'use', child: Text(st.t('m_use'))),
                            PopupMenuItem(value: 'rename', child: Text(st.t('f_rename'))),
                            PopupMenuItem(value: 'copy', child: Text(st.t('m_copy_ip'))),
                            PopupMenuItem(value: 'del', child: Text(st.t('m_delete_list'))),
                          ],
                        ),
                      );
                    }),
          )),
        ]),
      );
}

// ---------------------------------------------------------------- تنظیمات
class SettingsDialog extends StatefulWidget {
  final AppState st;
  const SettingsDialog({super.key, required this.st});
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late String lang = widget.st.lang;
  late final dirC = TextEditingController(text: widget.st.recvDir);
  late final portC = TextEditingController(text: widget.st.port.toString());
  late final ipC = TextEditingController(text: widget.st.manualIp);
  late final nameC = TextEditingController(text: widget.st.deviceName);
  AppState get st => widget.st;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(st.t('st_title')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(st.t('lang')),
            DropdownButton<String>(
              value: lang,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'fa', child: Text('فارسی')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) => setState(() => lang = v ?? lang),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: dirC, decoration: InputDecoration(labelText: st.t('recv_dir')))),
              IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: () async {
                  final d = await FilePicker.platform.getDirectoryPath();
                  if (d != null) setState(() => dirC.text = d);
                },
              ),
            ]),
            TextField(
                controller: portC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: st.t('port'))),
            TextField(
                controller: ipC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: st.t('ip'))),
            TextField(controller: nameC, decoration: InputDecoration(labelText: st.t('name'))),
            const SizedBox(height: 8),
            Text(st.t('note'), style: const TextStyle(fontSize: 12, color: kGray)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(st.t('cancel'))),
          TextButton(
            onPressed: () async {
              final p = int.tryParse(portC.text.trim());
              if (p == null || p < 1024 || p > 65535) {
                st.toast(st.t('bad_port'));
                return;
              }
              await st.applySettings(
                  newLang: lang, newDir: dirC.text.trim(), newPort: p, ip: ipC.text.trim(), name: nameC.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: Text(st.t('save')),
          ),
        ],
      );
}

// ---------------------------------------------------------------- صفحه اصلی
class HomePage extends StatefulWidget {
  final AppState st;
  const HomePage({super.key, required this.st});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController tc;
  AppState get st => widget.st;

  @override
  void initState() {
    super.initState();
    tc = TabController(length: 4, vsync: this);
    tc.addListener(() {
      if (tc.index == 1) {
        st.setReceiveMode(true);
      } else if (tc.index == 0) {
        st.setReceiveMode(false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await st.ensureStorage();
      await st.ensureRecvDir();
      st.syncSendRoots();
    });
  }

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  void _useFav(Fav f) {
    st.devices[f.ip] = f.name;
    st.pendingIp = f.ip;
    tc.animateTo(0);
    st.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final on = st.receiveMode;
    return Scaffold(
      backgroundColor: kBorder,
      appBar: AppBar(
        backgroundColor: kBorder,
        foregroundColor: Colors.white,
        title: Text(st.t('title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => showDialog(context: context, builder: (_) => SettingsDialog(st: st)),
          ),
        ],
        bottom: TabBar(
          controller: tc,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(icon: const Icon(Icons.send), text: st.t('tab_send')),
            Tab(icon: const Icon(Icons.download), text: st.t('tab_recv')),
            Tab(icon: const Icon(Icons.history), text: st.t('tab_hist')),
            Tab(icon: const Icon(Icons.star), text: st.t('tab_fav')),
          ],
        ),
      ),
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(5, 0, 5, 5),
          color: kBg,
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Wrap(spacing: 12, children: [
                Text(fmt(st.t('me'), {'name': st.deviceName, 'ip': st.myIp, 'port': st.port}),
                    style: const TextStyle(color: kBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                Text(st.t(on ? 'mode_on' : 'mode_off'),
                    style: TextStyle(color: on ? kGreen : kGray, fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
            ),
            Expanded(
              child: TabBarView(
                controller: tc,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  SendTab(st: st),
                  RecvTab(st: st),
                  HistTab(st: st),
                  FavTab(st: st, onUse: _useFav),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xFFE3EEF9),
              padding: const EdgeInsets.all(8),
              child: Text(st.status, style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- شروع برنامه
class FileShareApp extends StatelessWidget {
  final AppState st;
  const FileShareApp({super.key, required this.st});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: st,
        builder: (context, _) => MaterialApp(
          navigatorKey: navKey,
          scaffoldMessengerKey: msgKey,
          debugShowCheckedModeBanner: false,
          title: 'FileShare',
          theme: ThemeData(primaryColor: kBorder, colorScheme: ColorScheme.fromSeed(seedColor: kBorder)),
          builder: (ctx, child) => Directionality(
            textDirection: st.lang == 'fa' ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
          home: HomePage(st: st),
        ),
      );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final st = AppState();
  await st.init();
  runApp(FileShareApp(st: st));
}
