import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://dallini-app.onrender.com');
const services = ['كهرباء', 'سباكة', 'تكييف', 'صيانة أجهزة', 'تنظيف', 'سيارات'];
const serviceIcons = [Icons.bolt, Icons.water_drop, Icons.ac_unit, Icons.build, Icons.cleaning_services, Icons.directions_car];
const serviceColors = [Colors.amber, Colors.blue, Colors.cyan, Colors.deepPurple, Colors.green, Colors.red];

void main() => runApp(const DalliniApp());

class DalliniApp extends StatelessWidget {
  const DalliniApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'دلّيني',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff087e8b)),
        home: const Directionality(textDirection: TextDirection.rtl, child: RootPage()),
      );
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override State<RootPage> createState() => _RootPageState();
}
class _RootPageState extends State<RootPage> {
  Map<String, dynamic>? user;
  bool loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('user');
    if (raw != null) {
      try { user = Map<String, dynamic>.from(jsonDecode(raw) as Map); } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> _done(String token, Map<String, dynamic> account) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token);
    await p.setString('user', jsonEncode(account));
    if (mounted) setState(() => user = account);
  }
  Future<void> _logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('user');
    if (mounted) setState(() => user = null);
  }
  @override Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return user == null ? LoginPage(onDone: _done) : MainShell(user: user!, onLogout: _logout);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onDone});
  final Future<void> Function(String, Map<String, dynamic>) onDone;
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  bool register = false;
  bool busy = false;
  String role = 'customer';
  @override void dispose() { name.dispose(); phone.dispose(); password.dispose(); super.dispose(); }
  void msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> submit() async {
    if (phone.text.trim().length < 9 || password.text.length < 6) { msg('أدخل رقم هاتف صحيح وكلمة مرور من 6 أحرف على الأقل'); return; }
    if (register && name.text.trim().length < 2) { msg('أدخل الاسم الكامل'); return; }
    setState(() => busy = true);
    try {
      final endpoint = register ? 'register' : 'login';
      final r = await http.post(Uri.parse('$apiUrl/api/auth/$endpoint'), headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'name': name.text.trim(), 'phone': phone.text.trim(), 'password': password.text, 'role': role})).timeout(const Duration(seconds: 15));
      final body = jsonDecode(r.body);
      final data = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
      if (r.statusCode >= 200 && r.statusCode < 300 && data['user'] is Map) {
        await widget.onDone('${data['token']}', Map<String, dynamic>.from(data['user'] as Map));
      } else { msg('${data['error'] ?? 'تعذر إتمام العملية'}'); }
    } catch (_) { msg('تعذر الاتصال بالخادم'); }
    if (mounted) setState(() => busy = false);
  }
  @override Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xff063c59), Color(0xff1aa0b8)])), child: const Text('دلّيني', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900))),
          const SizedBox(height: 18), Text(register ? 'إنشاء حساب' : 'تسجيل الدخول', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          if (register) TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم الكامل', border: OutlineInputBorder())),
          if (register) const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
          if (register) const SizedBox(height: 12),
          if (register) DropdownButtonFormField<String>(initialValue: role, decoration: const InputDecoration(labelText: 'نوع الحساب', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'customer', child: Text('مستخدم / طالب خدمة')), DropdownMenuItem(value: 'provider', child: Text('فني / مقدم خدمة'))], onChanged: (v) { if (v != null) setState(() => role = v); }),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'جاري...' : (register ? 'إنشاء الحساب' : 'دخول')))),
          TextButton(onPressed: busy ? null : () => setState(() => register = !register), child: Text(register ? 'لدي حساب بالفعل' : 'إنشاء حساب جديد')),
        ]))))),
      );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.user, required this.onLogout});
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;
  @override State<MainShell> createState() => _MainShellState();
}
class _MainShellState extends State<MainShell> {
  int index = 0;
  @override Widget build(BuildContext context) {
    final provider = widget.user['role'] == 'provider';
    if (provider) {
      final pages = [const ProviderJobsPage(), ProfilePage(user: widget.user, onLogout: widget.onLogout)];
      return Scaffold(body: IndexedStack(index: index, children: pages), bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [NavigationDestination(icon: Icon(Icons.work_outline), label: 'الطلبات'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي')]));
    }
    final pages = [const HomePage(), const OrdersPage(), const SizedBox.shrink(), const MessagesPage(), ProfilePage(user: widget.user, onLogout: widget.onLogout)];
    return Scaffold(body: IndexedStack(index: index, children: pages), bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) { if (v == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => const NewRequestPage())); } else { setState(() => index = v); } }, destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), label: 'الرئيسية'), NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'طلباتي'), NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'طلب جديد'), NavigationDestination(icon: Icon(Icons.chat_outlined), label: 'المحادثات'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي')]));
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(colors: [Color(0xff063c59), Color(0xff1aa0b8)])), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('دلّيني', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)), SizedBox(height: 6), Text('عندك مشكلة؟ خلّينا نحلّها.', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)), SizedBox(height: 5), Text('اختار الخدمة ونوصل لك فني مناسب.', style: TextStyle(color: Colors.white70))])),
        const SizedBox(height: 20), const Text('شنو تحتاج اليوم؟', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 12),
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: services.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.15), itemBuilder: (_, i) => Card(child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewRequestPage(service: services[i]))), child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: [serviceColors[i].withAlpha(55), Colors.white])), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircleAvatar(radius: 29, backgroundColor: serviceColors[i].withAlpha(45), foregroundColor: serviceColors[i], child: Icon(serviceIcons[i], size: 31)), const SizedBox(height: 8), Text(services[i], style: const TextStyle(fontWeight: FontWeight.w900))]))))),
        const SizedBox(height: 16), Card(child: ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewRequestPage())), leading: const CircleAvatar(child: Icon(Icons.add)), title: const Text('إنشاء طلب جديد', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: const Text('اكتب المشكلة وأرسلها للفنيين'), trailing: const Icon(Icons.chevron_left))),
      ]);
}

class NewRequestPage extends StatefulWidget {
  const NewRequestPage({super.key, this.service});
  final String? service;
  @override State<NewRequestPage> createState() => _NewRequestPageState();
}
class _NewRequestPageState extends State<NewRequestPage> {
  final desc = TextEditingController(); final address = TextEditingController();
  String? service; bool busy = false;
  @override void initState() { super.initState(); service = widget.service; }
  @override void dispose() { desc.dispose(); address.dispose(); super.dispose(); }
  void msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> send() async {
    if (service == null) { msg('اختر نوع الخدمة'); return; }
    if (desc.text.trim().length < 4) { msg('اكتب وصف المشكلة'); return; }
    final p = await SharedPreferences.getInstance(); final token = p.getString('token') ?? '';
    if (token.isEmpty) { msg('سجّل الدخول مرة أخرى'); return; }
    setState(() => busy = true);
    try {
      final r = await http.post(Uri.parse('$apiUrl/api/requests'), headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}, body: jsonEncode({'category': service, 'description': desc.text.trim(), 'address': address.text.trim()})).timeout(const Duration(seconds: 15));
      final body = jsonDecode(r.body); final data = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
      if (r.statusCode >= 200 && r.statusCode < 300) { if (mounted) { msg('تم إرسال الطلب بنجاح'); Navigator.pop(context); } } else { msg('${data['error'] ?? 'تعذر إرسال الطلب'}'); }
    } catch (_) { msg('تعذر الاتصال بالخادم'); }
    if (mounted) setState(() => busy = false);
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('طلب جديد')), body: ListView(padding: const EdgeInsets.all(18), children: [
        DropdownButtonFormField<String>(initialValue: service, decoration: const InputDecoration(labelText: 'نوع الخدمة', border: OutlineInputBorder()), items: services.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => service = v)),
        const SizedBox(height: 14), TextField(controller: desc, minLines: 4, maxLines: 7, decoration: const InputDecoration(labelText: 'وصف المشكلة', border: OutlineInputBorder())),
        const SizedBox(height: 14), TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder())),
        const SizedBox(height: 20), SizedBox(height: 52, child: FilledButton.icon(onPressed: busy ? null : send, icon: const Icon(Icons.send), label: Text(busy ? 'جاري الإرسال...' : 'إرسال الطلب'))),
      ]);
}

Future<Map<String, String>> authHeaders() async { final p = await SharedPreferences.getInstance(); return {'Authorization': 'Bearer ${p.getString('token') ?? ''}'}; }

class OrdersPage extends StatefulWidget { const OrdersPage({super.key}); @override State<OrdersPage> createState() => _OrdersPageState(); }
class _OrdersPageState extends State<OrdersPage> {
  List<Map<String, dynamic>> items = []; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { try { final r = await http.get(Uri.parse('$apiUrl/api/requests/mine'), headers: await authHeaders()).timeout(const Duration(seconds: 15)); if (r.statusCode == 200) { final body = jsonDecode(r.body); items = body is List ? body.map((e) => Map<String, dynamic>.from(e as Map)).toList() : []; } } catch (_) {} if (mounted) setState(() => loading = false); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('طلباتي')), body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load, child: items.isEmpty ? ListView(children: const [SizedBox(height: 180), Center(child: Text('لا توجد طلبات بعد'))]) : ListView.builder(itemCount: items.length, itemBuilder: (_, i) { final x = items[i]; return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RequestDetailsPage(id: '${x['id']}'))), leading: const CircleAvatar(child: Icon(Icons.receipt_long)), title: Text('${x['category'] ?? 'طلب'}'), subtitle: Text('${x['description'] ?? ''}\nالحالة: ${x['status'] ?? ''}'), isThreeLine: true, trailing: const Icon(Icons.chevron_left))); }));
}

class RequestDetailsPage extends StatefulWidget { const RequestDetailsPage({super.key, required this.id}); final String id; @override State<RequestDetailsPage> createState() => _RequestDetailsPageState(); }
class _RequestDetailsPageState extends State<RequestDetailsPage> {
  Map<String, dynamic>? request; List<Map<String, dynamic>> offers = []; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { try { final h = await authHeaders(); final a = await http.get(Uri.parse('$apiUrl/api/requests/${widget.id}'), headers: h); final b = await http.get(Uri.parse('$apiUrl/api/requests/${widget.id}/offers'), headers: h); if (a.statusCode == 200) request = Map<String, dynamic>.from(jsonDecode(a.body) as Map); if (b.statusCode == 200) { final raw = jsonDecode(b.body); offers = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : []; } } catch (_) {} if (mounted) setState(() => loading = false); }
  Future<void> next() async { try { final r = await http.post(Uri.parse('$apiUrl/api/requests/${widget.id}/next'), headers: await authHeaders()); if (r.statusCode >= 200 && r.statusCode < 300) await load(); } catch (_) {} }
  Future<void> cancel() async { try { final r = await http.post(Uri.parse('$apiUrl/api/requests/${widget.id}/cancel'), headers: await authHeaders()); if (r.statusCode >= 200 && r.statusCode < 300) await load(); } catch (_) {} }
  Future<void> accept(String providerId) async { try { final h = await authHeaders(); final r = await http.post(Uri.parse('$apiUrl/api/requests/${widget.id}/accept-offer'), headers: {...h, 'Content-Type': 'application/json'}, body: jsonEncode({'providerId': providerId})); if (r.statusCode >= 200 && r.statusCode < 300) await load(); } catch (_) {} }
  @override Widget build(BuildContext context) { if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator())); if (request == null) return const Scaffold(body: Center(child: Text('تعذر تحميل تفاصيل الطلب'))); final x = request!; return Scaffold(appBar: AppBar(title: const Text('تفاصيل الطلب')), body: ListView(padding: const EdgeInsets.all(18), children: [Card(child: ListTile(title: Text('${x['category']}'), subtitle: Text('${x['description']}\nالعنوان: ${x['address'] ?? '-'}\nالحالة: ${x['status']}'))), const SizedBox(height: 12), if (offers.isNotEmpty) ...[const Text('العروض', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), ...offers.map((o) => Card(child: ListTile(title: Text('${o['name'] ?? 'فني'}'), subtitle: Text('السعر: ${o['price'] ?? '-'}  |  الوصول: ${o['eta'] ?? '-'}'), trailing: FilledButton(onPressed: () => accept('${o['provider_id'] ?? o['id'] ?? 1}'), child: const Text('قبول')))))], const SizedBox(height: 14), FilledButton.tonal(onPressed: next, child: const Text('تحديث حالة الطلب')), const SizedBox(height: 8), OutlinedButton(onPressed: x['status'] == 'completed' ? null : cancel, child: const Text('إلغاء الطلب'))])); }
}

class MessagesPage extends StatelessWidget { const MessagesPage({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('المحادثات')), body: ListView(children: const [ListTile(leading: CircleAvatar(child: Icon(Icons.support_agent)), title: Text('دعم دلّيني'), subtitle: Text('ستظهر هنا محادثات الطلبات والفنيين.'))])); }

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.user, required this.onLogout}); final Map<String, dynamic> user; final Future<void> Function() onLogout;
  @override Widget build(BuildContext context) { final entries = [('تعديل الملف الشخصي', Icons.edit_outlined, 'يمكنك تعديل الاسم ورقم الهاتف.'), ('العناوين', Icons.location_on_outlined, 'إدارة عناوينك المحفوظة.'), ('الفنيين المفضلين', Icons.favorite_outline, 'ستظهر هنا قائمة الفنيين المفضلين.'), ('الخصوصية والأمان', Icons.security_outlined, 'إعدادات حماية الحساب.'), ('الإشعارات', Icons.notifications_outlined, 'إدارة إشعارات الطلبات.'), ('المساعدة', Icons.help_outline, 'الأسئلة الشائعة والدعم.')]; return Scaffold(appBar: AppBar(title: const Text('حسابي')), body: ListView(padding: const EdgeInsets.all(16), children: [Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text('${user['name'] ?? 'مستخدم'}', style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${user['phone'] ?? ''}'))), const SizedBox(height: 10), ...entries.map((e) => Card(child: ListTile(leading: Icon(e.$2), title: Text(e.$1), subtitle: Text(e.$3), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SimplePage(title: e.$1, icon: e.$2, text: e.$3))))), const SizedBox(height: 12), FilledButton.tonalIcon(onPressed: onLogout, icon: const Icon(Icons.logout), label: const Text('تسجيل الخروج'))])); }
}

class SimplePage extends StatelessWidget {
  const SimplePage({super.key, required this.title, required this.icon, required this.text}); final String title; final IconData icon; final String text;
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 36, child: Icon(icon, size: 36)), const SizedBox(height: 16), Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 10), Text(text, textAlign: TextAlign.center)]))))));
}

class ProviderJobsPage extends StatefulWidget { const ProviderJobsPage({super.key}); @override State<ProviderJobsPage> createState() => _ProviderJobsPageState(); }
class _ProviderJobsPageState extends State<ProviderJobsPage> {
  List<Map<String, dynamic>> jobs = []; bool loading = true;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { try { final r = await http.get(Uri.parse('$apiUrl/api/providers/requests'), headers: await authHeaders()); if (r.statusCode == 200) { final raw = jsonDecode(r.body); jobs = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : []; } } catch (_) {} if (mounted) setState(() => loading = false); }
  Future<void> accept(String id) async { try { final r = await http.post(Uri.parse('$apiUrl/api/providers/requests/$id/accept'), headers: await authHeaders()); if (r.statusCode >= 200 && r.statusCode < 300) await load(); } catch (_) {} }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('طلبات الفنيين')), body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: load, child: ListView.builder(itemCount: jobs.length, itemBuilder: (_, i) { final x = jobs[i]; return Card(margin: const EdgeInsets.all(10), child: ListTile(title: Text('${x['category'] ?? 'طلب'}'), subtitle: Text('${x['description'] ?? ''}\n${x['address'] ?? ''}'), isThreeLine: true, trailing: FilledButton(onPressed: () => accept('${x['id']}'), child: const Text('قبول')))); }));
}
