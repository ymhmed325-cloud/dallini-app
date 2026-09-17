import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://dallini-app.onrender.com');

const services = <String>['كهرباء', 'سباكة', 'تكييف', 'صيانة أجهزة', 'تنظيف', 'سيارات'];
const serviceIcons = <IconData>[
  Icons.bolt,
  Icons.water_drop,
  Icons.ac_unit,
  Icons.build,
  Icons.cleaning_services,
  Icons.directions_car,
];
const serviceColors = <Color>[
  Colors.amber,
  Colors.blue,
  Colors.cyan,
  Colors.deepPurple,
  Colors.green,
  Colors.red,
];

void main() => runApp(const DalliniApp());

class DalliniApp extends StatelessWidget {
  const DalliniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دلّيني',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0b7a8a)),
        scaffoldBackgroundColor: const Color(0xfff5f8fa),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: Root(),
      ),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  Map<String, dynamic>? user;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString('user');
    final token = prefs.getString('token');
    if (rawUser != null && token != null && token.isNotEmpty) {
      try {
        user = Map<String, dynamic>.from(jsonDecode(rawUser) as Map);
      } catch (_) {
        await prefs.remove('user');
        await prefs.remove('token');
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> saveSession(String token, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('user', jsonEncode(value));
    if (mounted) setState(() => user = value);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    if (mounted) setState(() => user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return user == null
        ? LoginPage(onDone: saveSession)
        : AppShell(user: user!, onLogout: logout);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onDone});

  final Future<void> Function(String token, Map<String, dynamic> user) onDone;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool register = false;
  bool busy = false;
  String role = 'customer';

  void snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> submit() async {
    final p = phone.text.trim();
    if (p.length < 9 || password.text.length < 6) {
      snack('أدخل رقم هاتف صحيح وكلمة مرور من 6 أحرف على الأقل');
      return;
    }
    if (register && name.text.trim().length < 2) {
      snack('أدخل الاسم الكامل');
      return;
    }
    setState(() => busy = true);
    try {
      final action = register ? 'register' : 'login';
      final response = await http
          .post(
            Uri.parse('$apiUrl/api/auth/$action'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name.text.trim(),
              'phone': p,
              'password': password.text,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await widget.onDone(
          '${data['token']}',
          Map<String, dynamic>.from(data['user'] as Map),
        );
      } else {
        snack('${data['error'] ?? 'تعذر تسجيل الدخول'}');
      }
    } catch (_) {
      snack('تعذر الاتصال بالخادم');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    phone.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      Container(
                        height: 110,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                          gradient: LinearGradient(
                            colors: [Color(0xff064b63), Color(0xff1597ad)],
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'دلّيني',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        register ? 'إنشاء حساب' : 'تسجيل الدخول',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 18),
                      if (register) ...[
                        TextField(
                          controller: name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'الاسم الكامل',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (register) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: role,
                          decoration: const InputDecoration(
                            labelText: 'نوع الحساب',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'customer',
                              child: Text('مستخدم / طالب خدمة'),
                            ),
                            DropdownMenuItem(
                              value: 'provider',
                              child: Text('فني / مقدم خدمة'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => role = value);
                          },
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: busy ? null : submit,
                          child: Text(
                            busy ? 'جاري...' : (register ? 'إنشاء الحساب' : 'دخول'),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => setState(() => register = !register),
                        child: Text(register ? 'لدي حساب بالفعل' : 'إنشاء حساب جديد'),
                      ),
                      const Text(
                        'الحساب مرتبط بالخادم الحقيقي.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.user, required this.onLogout});

  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  int refreshTick = 0;

  Future<void> openRequest([String? service]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewRequest(service: service)),
    );
    if (!mounted) return;
    setState(() {
      refreshTick++;
      index = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.user['role'] == 'provider';
    if (provider) {
      return Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            ProviderJobs(user: widget.user),
            ProviderProfile(user: widget.user, onLogout: widget.onLogout),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الطلبات'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
          ],
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          Home(onNew: openRequest),
          Orders(key: ValueKey(refreshTick)),
          const SizedBox.shrink(),
          const MessagesPage(),
          Profile(user: widget.user, onLogout: widget.onLogout),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          if (value == 2) {
            openRequest();
          } else {
            setState(() => index = value);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'طلباتي'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'طلب جديد'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'المحادثات'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key, required this.onNew});
  final Future<void> Function([String?]) onNew;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(28)),
              gradient: LinearGradient(colors: [Color(0xff063c59), Color(0xff1aa0b8)]),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('دلّيني', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text('عندك مشكلة؟ خلّينا نحلّها.', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('اختار الخدمة ونوصل لك فني مناسب قريب منك.', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('شنو تحتاج اليوم؟', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: services.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.18,
            ),
            itemBuilder: (_, i) {
              final c = serviceColors[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onNew(services[i]),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [c.withOpacity(.18), Colors.white]),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: c.withOpacity(.18),
                          foregroundColor: c,
                          child: Icon(serviceIcons[i], size: 31),
                        ),
                        const SizedBox(height: 8),
                        Text(services[i], style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              onTap: () => onNew(),
              leading: const CircleAvatar(child: Icon(Icons.add)),
              title: const Text('إنشاء طلب جديد', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: const Text('أرسل المشكلة والصورة والصوت والموقع'),
              trailing: const Icon(Icons.chevron_left),
            ),
          ),
        ],
      ),
    );
  }
}

class Orders extends StatefulWidget {
  const Orders({super.key});

  @override
  State<Orders> createState() => _OrdersState();
}

class _OrdersState extends State<Orders> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/api/requests/mine'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        items = (jsonDecode(response.body) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String statusText(dynamic value) {
    const map = {
      'matching': 'جاري البحث عن فني',
      'offer': 'وصل عرض فني',
      'accepted': 'تم قبول الفني',
      'on_way': 'الفني بالطريق',
      'arrived': 'وصل الفني',
      'in_progress': 'قيد التنفيذ',
      'completed': 'مكتمل',
      'cancelled': 'ملغي',
    };
    return map[value] ?? '$value';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, size: 70, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('ما عندك طلبات بعد', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewRequest())).then((_) => load()),
              icon: const Icon(Icons.add),
              label: const Text('إنشاء طلب'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          final idx = services.indexOf('${item['category']}');
          final k = idx >= 0 ? idx : 0;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: serviceColors[k].withOpacity(.18),
                foregroundColor: serviceColors[k],
                child: Icon(serviceIcons[k]),
              ),
              title: Text('${item['category']}', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${item['description']}\n${statusText(item['status'])}'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RequestDetail(request: item)),
              ).then((_) => load()),
            ),
          );
        },
      ),
    );
  }
}

class NewRequest extends StatefulWidget {
  const NewRequest({super.key, this.service});
  final String? service;

  @override
  State<NewRequest> createState() => _NewRequestState();
}

class _NewRequestState extends State<NewRequest> {
  final description = TextEditingController();
  final address = TextEditingController();
  final picker = ImagePicker();
  final recorder = AudioRecorder();
  String? service;
  String? imagePath;
  String? audioPath;
  Position? position;
  bool locating = false;
  bool recording = false;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    service = widget.service;
  }

  void snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> chooseImage(ImageSource source) async {
    try {
      final file = await picker.pickImage(source: source, imageQuality: 85);
      if (file != null && mounted) setState(() => imagePath = file.path);
    } catch (_) {
      snack('تعذر فتح الصور');
    }
  }

  Future<void> selectImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('الكاميرا'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('المعرض'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await chooseImage(source);
  }

  Future<void> toggleVoice() async {
    try {
      if (recording) {
        final path = await recorder.stop();
        if (mounted) {
          setState(() {
            recording = false;
            audioPath = path;
          });
        }
        return;
      }
      if (!await recorder.hasPermission()) {
        snack('اسمح باستخدام الميكروفون');
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = '${dir.path}/dallini_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: file,
      );
      if (mounted) setState(() => recording = true);
    } catch (_) {
      snack('تعذر تسجيل الصوت');
    }
  }

  Future<void> getLocation() async {
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        snack('فعّل خدمة الموقع من الهاتف');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        snack('اسمح للتطبيق باستخدام الموقع');
        return;
      }
      position = await Geolocator.getCurrentPosition();
      address.text = 'الموقع الحالي: ${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}';
      if (mounted) setState(() {});
    } catch (_) {
      snack('تعذر تحديد الموقع');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> send() async {
    if (service == null || service!.isEmpty) {
      snack('اختر نوع الخدمة');
      return;
    }
    if (description.text.trim().length < 3) {
      snack('اكتب وصف المشكلة');
      return;
    }
    setState(() => sending = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    try {
      final response = await http
          .post(
            Uri.parse('$apiUrl/api/requests'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'category': service,
              'description': description.text.trim(),
              'address': address.text.trim(),
              'lat': position?.latitude,
              'lng': position?.longitude,
              'hasImage': imagePath != null,
              'hasAudio': audioPath != null,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }
      final data = jsonDecode(response.body);
      snack('${data['error'] ?? 'تعذر إرسال الطلب'}');
    } catch (_) {
      snack('تعذر الاتصال بالخادم');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    description.dispose();
    address.dispose();
    recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلب جديد')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          DropdownButtonFormField<String>(
            value: service,
            decoration: const InputDecoration(labelText: 'الخدمة', border: OutlineInputBorder()),
            items: services.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (value) => setState(() => service = value),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: description,
            minLines: 4,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'وصف المشكلة',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: Icon(imagePath == null ? Icons.image_outlined : Icons.check_circle),
              title: Text(imagePath == null ? 'إضافة صورة' : 'تمت إضافة الصورة'),
              trailing: FilledButton(onPressed: selectImage, child: const Text('اختيار')),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(recording ? Icons.stop_circle : Icons.mic_none),
              title: Text(recording ? 'جاري التسجيل...' : (audioPath == null ? 'إضافة تسجيل صوتي' : 'تم تسجيل الصوت')),
              trailing: FilledButton(
                onPressed: toggleVoice,
                child: Text(recording ? 'إيقاف' : 'تسجيل'),
              ),
            ),
          ),
          TextField(
            controller: address,
            decoration: InputDecoration(
              labelText: 'الموقع / العنوان',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: locating ? null : getLocation,
                icon: locating ? const CircularProgressIndicator() : const Icon(Icons.my_location),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: sending ? null : send,
              icon: const Icon(Icons.send),
              label: Text(sending ? 'جاري إرسال الطلب...' : 'إرسال الطلب'),
            ),
          ),
        ],
      ),
    );
  }
}

class RequestDetail extends StatefulWidget {
  const RequestDetail({super.key, required this.request});
  final Map<String, dynamic> request;

  @override
  State<RequestDetail> createState() => _RequestDetailState();
}

class _RequestDetailState extends State<RequestDetail> {
  late Map<String, dynamic> item;
  List<dynamic> offers = [];
  bool loading = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    item = Map<String, dynamic>.from(widget.request);
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/api/requests/${item['id']}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        item = Map<String, dynamic>.from(data['request'] as Map);
        offers = data['offers'] as List? ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> accept(dynamic offerId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    setState(() => busy = true);
    try {
      await http.post(
        Uri.parse('$apiUrl/api/requests/${widget.id}/accept-offer'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );
      await load();
    } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  Future<void> nextStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    setState(() => busy = true);
    try {
      await http.post(
        Uri.parse('$apiUrl/api/requests/${item['id']}/next'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );
      await load();
    } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  Future<void> cancel() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    setState(() => busy = true);
    try {
      await http.post(
        Uri.parse('$apiUrl/api/requests/${item['id']}/cancel'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );
      await load();
    } catch (_) {}
    if (mounted) setState(() => busy = false);
  }

  String statusText(dynamic value) {
    const map = {
      'matching': 'جاري البحث عن فني',
      'offer': 'وصل عرض فني',
      'accepted': 'تم قبول الفني',
      'on_way': 'الفني بالطريق',
      'arrived': 'وصل الفني',
      'in_progress': 'قيد التنفيذ',
      'completed': 'مكتمل',
      'cancelled': 'ملغي',
    };
    return map[value] ?? '$value';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text('تفاصيل الطلب #${item['id']}')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item['category']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text('${item['description']}'),
                    const SizedBox(height: 12),
                    Text('الحالة: ${statusText(item['status'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if ('${item['address']}'.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('الموقع: ${item['address']}'),
                    ],
                  ],
                ),
              ),
            ),
            if (offers.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('عروض الفنيين', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              ...offers.map(
                (offer) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.engineering)),
                    title: Text('${offer['providerName'] ?? 'فني'}'),
                    subtitle: Text('${offer['price'] ?? '-'} د.ع • ${offer['eta'] ?? '-'} دقيقة'),
                    trailing: FilledButton(
                      onPressed: busy ? null : () => accept(offer['id']),
                      child: const Text('قبول'),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (item['status'] != 'completed' && item['status'] != 'cancelled') ...[
              FilledButton.icon(
                onPressed: busy ? null : nextStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث حالة الطلب'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('إلغاء الطلب'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProviderJobs extends StatefulWidget {
  const ProviderJobs({super.key, required this.user});
  final Map<String, dynamic> user;

  @override
  State<ProviderJobs> createState() => _ProviderJobsState();
}

class _ProviderJobsState extends State<ProviderJobs> {
  List<dynamic> jobs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/api/providers/requests'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) jobs = jsonDecode(response.body) as List;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> accept(dynamic id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    try {
      await http.post(
        Uri.parse('$apiUrl/api/providers/requests/$id/accept'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );
      await load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('الطلبات المتاحة', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  if (jobs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('لا توجد طلبات متاحة حالياً')),
                    ),
                  ...jobs.map(
                    (job) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.assignment)),
                        title: Text('${job['category']}'),
                        subtitle: Text('${job['description']}'),
                        trailing: FilledButton(
                          onPressed: () => accept(job['id']),
                          child: const Text('قبول'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 72, color: Colors.grey),
            SizedBox(height: 12),
            Text('لا توجد محادثات بعد', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class Profile extends StatelessWidget {
  const Profile({super.key, required this.user, required this.onLogout});
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(radius: 30, child: Icon(Icons.person)),
              title: Text('${user['name'] ?? 'المستخدم'}', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${user['phone'] ?? ''}'),
            ),
          ),
          const SizedBox(height: 10),
          _item(context, Icons.edit_outlined, 'تعديل الملف الشخصي', const EditProfilePage()),
          _item(context, Icons.location_on_outlined, 'العناوين', const AddressesPage()),
          _item(context, Icons.notifications_outlined, 'الإشعارات', const NotificationsPage()),
          _item(context, Icons.settings_outlined, 'الإعدادات', const SettingsPage()),
          _item(context, Icons.lock_outline, 'الأمان والخصوصية', const SecurityPage()),
          _item(context, Icons.help_outline, 'المساعدة', const HelpPage()),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String title, Widget page) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: page))),
      ),
    );
  }
}

class ProviderProfile extends StatelessWidget {
  const ProviderProfile({super.key, required this.user, required this.onLogout});
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => Profile(user: user, onLogout: onLogout);
}

class EditProfilePage extends StatelessWidget {
  const EditProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final name = TextEditingController();
    final phone = TextEditingController();
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم الكامل', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تجهيز صفحة التعديل للحفظ مع الحساب'))),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class AddressesPage extends StatefulWidget {
  const AddressesPage({super.key});

  @override
  State<AddressesPage> createState() => _AddressesPageState();
}

class _AddressesPageState extends State<AddressesPage> {
  final List<String> addresses = [];

  Future<void> addAddress() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة عنوان'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'العنوان')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('إضافة')),
        ],
      ),
    );
    if (value != null && value.trim().isNotEmpty && mounted) {
      setState(() => addresses.add(value.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العناوين')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (addresses.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا توجد عناوين محفوظة'))),
          ...addresses.map(
            (address) => Card(
              child: ListTile(
                leading: const Icon(Icons.location_on),
                title: Text(address),
                trailing: IconButton(
                  onPressed: () => setState(() => addresses.remove(address)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: addAddress, icon: const Icon(Icons.add), label: const Text('إضافة عنوان')),
        ],
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: const ListView(
        children: [
          ListTile(leading: Icon(Icons.notifications_active), title: Text('إشعارات الطلبات'), subtitle: Text('ستظهر تحديثات طلباتك هنا')),
          ListTile(leading: Icon(Icons.info_outline), title: Text('حالة الحساب'), subtitle: Text('الحساب مرتبط بالخادم')),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool notifications = true;
  bool location = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          SwitchListTile(
            value: notifications,
            onChanged: (value) => setState(() => notifications = value),
            title: const Text('إشعارات الطلبات'),
          ),
          SwitchListTile(
            value: location,
            onChanged: (value) => setState(() => location = value),
            title: const Text('السماح بالموقع عند الطلب'),
          ),
          const ListTile(title: Text('الإصدار'), trailing: Text('2.2.0')),
        ],
      ),
    );
  }
}

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأمان والخصوصية')),
      body: const ListView(
        children: [
          ListTile(leading: Icon(Icons.lock), title: Text('كلمة مرور للحساب'), subtitle: Text('حماية الحساب بكلمة مرور')),
          ListTile(leading: Icon(Icons.verified_user), title: Text('جلسة دخول آمنة'), subtitle: Text('يستخدم التطبيق رمز جلسة للخادم')),
          ListTile(leading: Icon(Icons.phone), title: Text('رقم الهاتف'), subtitle: Text('مرتبط بالحساب')),
        ],
      ),
    );
  }
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المساعدة')),
      body: ListView(
        children: const [
          ExpansionTile(
            title: Text('كيف أنشئ طلباً؟'),
            children: [Padding(padding: EdgeInsets.all(16), child: Text('اختر الخدمة، اكتب المشكلة، أضف صورة أو صوتاً وحدد موقعك ثم أرسل الطلب.'))],
          ),
          ExpansionTile(
            title: Text('كيف يعمل الفني؟'),
            children: [Padding(padding: EdgeInsets.all(16), child: Text('الفني ينشئ حساب فني ويشاهد الطلبات المتاحة ثم يقبل الطلب المناسب.'))],
          ),
          ExpansionTile(
            title: Text('هل يمكنني إلغاء الطلب؟'),
            children: [Padding(padding: EdgeInsets.all(16), child: Text('يمكن إلغاء الطلب من صفحة تفاصيل الطلب قبل اكتماله.'))],
          ),
        ],
      ),
    );
  }
}
