import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'location_service.dart';
import 'database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const FridayApp());
}

class FridayApp extends StatelessWidget {
  const FridayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Friday',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080810),
      ),
      home: const ChatScreen(),
    );
  }
}

class OrbPainter extends CustomPainter {
  final double pulse;
  final double plasma;
  OrbPainter({required this.pulse, required this.plasma});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.38;

    for (int i = 5; i >= 1; i--) {
      final r = baseRadius * (0.4 + i * 0.13) + sin(plasma + i) * 4;
      final opacity = (0.04 + i * 0.03).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = const Color(0xFF00D4FF).withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(center, r, paint);
    }

    for (int i = 0; i < 6; i++) {
      final angle = plasma * 0.7 + i * pi / 3;
      final dist = baseRadius * 0.72 + sin(plasma * 1.3 + i) * 6;
      final px = center.dx + cos(angle) * dist;
      final py = center.dy + sin(angle) * dist;
      final glowPaint = Paint()
        ..color = const Color(0xFF00D4FF).withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(px, py), 5 + sin(plasma + i) * 2, glowPaint);
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00D4FF).withOpacity(0.35 + pulse * 0.15),
          const Color(0xFF0044FF).withOpacity(0.12 + pulse * 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 0.55));
    canvas.drawCircle(center, baseRadius * 0.55, glowPaint);

    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00D4FF).withOpacity(0.9),
          const Color(0xFF0088FF).withOpacity(0.6),
          const Color(0xFF00D4FF).withOpacity(0.2),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 0.28));
    canvas.drawCircle(center, baseRadius * 0.28 + pulse * 3, corePaint);

    final linePaint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final crossDist = baseRadius * 0.92;
    final crossShort = baseRadius * 0.72;
    canvas.drawLine(Offset(center.dx, center.dy - crossDist),
        Offset(center.dx, center.dy - crossShort), linePaint);
    canvas.drawLine(Offset(center.dx, center.dy + crossShort),
        Offset(center.dx, center.dy + crossDist), linePaint);
    canvas.drawLine(Offset(center.dx - crossDist, center.dy),
        Offset(center.dx - crossShort, center.dy), linePaint);
    canvas.drawLine(Offset(center.dx + crossShort, center.dy),
        Offset(center.dx + crossDist, center.dy), linePaint);

    final dotPaint = Paint()
      ..color = const Color(0xFF00D4FF)
      ..style = PaintingStyle.fill;
    for (final angle in [0.0, pi / 2, pi, 3 * pi / 2]) {
      final dx = center.dx + cos(angle) * crossDist;
      final dy = center.dy + sin(angle) * crossDist;
      canvas.drawCircle(Offset(dx, dy), 3, dotPaint);
    }

    final diagPaint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.25)
      ..strokeWidth = 1.0;
    for (final angle in [pi / 4, 3 * pi / 4, 5 * pi / 4, 7 * pi / 4]) {
      final d1 = baseRadius * 0.78;
      final d2 = baseRadius * 0.92;
      canvas.drawLine(
        Offset(center.dx + cos(angle) * d1, center.dy + sin(angle) * d1),
        Offset(center.dx + cos(angle) * d2, center.dy + sin(angle) * d2),
        diagPaint,
      );
    }
  }

  @override
  bool shouldRepaint(OrbPainter old) => true;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  bool _modelReady = false;
  bool _isOnline = false;
  String _statusText = 'Loading AI model...';
  double _downloadProgress = 0;
  final LlamaController _llama = LlamaController();
  Timer? _locationTimer;
  Timer? _connectivityTimer;

  late AnimationController _pulseController;
  late AnimationController _plasmaController;
  late Animation<double> _pulseAnim;
  late Animation<double> _plasmaAnim;

  int _locationCount = 0;
  int _memoryCount = 0;
  int _messageCount = 0;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _plasmaController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _plasmaAnim = Tween<double>(begin: 0.0, end: 2 * pi).animate(
      CurvedAnimation(parent: _plasmaController, curve: Curves.linear),
    );

    _initFriday();
    _initLocation();
    _checkConnectivity();
    _loadStats();

    _connectivityTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkConnectivity();
    });
  }

  Future<void> _loadStats() async {
    final locations = await FridayDatabase.getRecentLocations();
    final memories = await FridayDatabase.getRecentMemories();
    final convos = await FridayDatabase.getRecentConversations(limit: 100);
    setState(() {
      _locationCount = locations.length;
      _memoryCount = memories.length;
      _messageCount = convos.length;
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning, boss.';
    if (hour < 17) return 'Good afternoon, boss.';
    return 'Good evening, boss.';
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (online != _isOnline) setState(() => _isOnline = online);
    } catch (_) {
      if (_isOnline) setState(() => _isOnline = false);
    }
  }

  Future<void> _initLocation() async {
    final hasPermission = await LocationService.requestPermission();
    if (hasPermission) {
      LocationService.startTracking();
      _locationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        LocationService.logCurrentLocation();
      });
      LocationService.logCurrentLocation();
    }
  }

  Future<void> _initFriday() async {
    setState(() => _isLoading = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/tinyllama.gguf';
      final file = File(modelPath);

      if (!await file.exists()) {
        setState(() => _statusText = 'Downloading AI model (637MB)...\nThis only happens once.');
        const url =
            'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(url));
        final response = await client.send(request);
        final totalBytes = response.contentLength ?? 0;
        final sink = file.openWrite();
        int received = 0;
        await response.stream.listen((chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (totalBytes > 0) {
            setState(() => _downloadProgress = received / totalBytes);
          }
        }).asFuture();
        await sink.close();
        client.close();
      }

      setState(() => _statusText = 'Initializing Friday...');
      await _llama.loadModel(
        modelPath: modelPath,
        threads: 6,
        contextSize: 512,
      );

      setState(() {
        _modelReady = true;
        _isLoading = false;
        _messages.add({
          'role': 'friday',
          'text': '${_getGreeting()} I\'m online and ready. What do you need?'
        });
      });
      _loadStats();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusText = 'Error: $e';
        _messages.add({'role': 'friday', 'text': 'Error: $e'});
      });
    }
  }

  Future<String> _askGroq(String userMessage) async {
    final apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    final memoryContext = await FridayDatabase.buildMemoryContext();

    final response = await http.post(
      Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'llama-3.3-70b-versatile',
        'messages': [
          {
            'role': 'system',
            'content':
                '''You are Friday, a personal AI assistant. You know everything about your user from their data below. Use this context naturally in your responses. Call the user "boss". Be helpful, informal and friendly like Iron Man\'s Friday.

PERSONAL DATA:
$memoryContext'''
          },
          {'role': 'user', 'content': userMessage}
        ],
        'max_tokens': 512,
        'temperature': 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'].trim();
    } else {
      throw Exception('Groq error: ${response.statusCode}');
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !_modelReady || _isLoading) return;

    await FridayDatabase.saveConversation(role: 'user', message: text);

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isLoading = true;
      _messages.add({'role': 'friday', 'text': ''});
    });
    _controller.clear();
    _scrollToBottom();

    try {
      String response = '';

      if (_isOnline) {
        response = await _askGroq(text);
        setState(() {
          _messages[_messages.length - 1] = {
            'role': 'friday',
            'text': response
          };
        });
      } else {
        final fullPrompt =
            '<|system|>You are Friday, a helpful AI assistant. Answer concisely in 1-2 sentences.</s><|user|>$text</s><|assistant|>';
        await for (final token in _llama.generate(
          prompt: fullPrompt,
          maxTokens: 128,
          temperature: 0.7,
          topP: 0.9,
          topK: 40,
        )) {
          response += token;
          setState(() {
            _messages[_messages.length - 1] = {
              'role': 'friday',
              'text': response
            };
          });
          _scrollToBottom();
        }
      }

      await FridayDatabase.saveConversation(
          role: 'friday', message: response.trim());
      setState(() => _isLoading = false);
      _loadStats();
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages[_messages.length - 1] = {
          'role': 'friday',
          'text': 'Error: $e'
        };
        _isLoading = false;
      });
    }
  }

  void _showMemories() async {
    final memories = await FridayDatabase.getRecentMemories();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF00D4FF22)),
      ),
      builder: (_) => _buildBottomSheet(
        title: 'MEMORIES',
        items: memories.map((m) => '${m['content']}').toList(),
        emptyText: 'No memories yet. Add some!',
      ),
    );
  }

  void _showLocations() async {
    final locations = await FridayDatabase.getRecentLocations();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF00D4FF22)),
      ),
      builder: (_) => _buildBottomSheet(
        title: 'LOCATIONS',
        items: locations.map((l) {
          final time = l['timestamp'].toString().substring(11, 16);
          return '${l['address']} · $time';
        }).toList(),
        emptyText: 'No locations logged yet.',
      ),
    );
  }

  void _showNoteDialog() {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D0D1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00D4FF33)),
        ),
        title: const Text('ADD NOTE',
            style: TextStyle(
                color: Color(0xFF00D4FF),
                fontSize: 13,
                letterSpacing: 3,
                fontFamily: 'monospace')),
        content: TextField(
          controller: noteController,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Tell Friday something...',
            hintStyle: TextStyle(color: Color(0xFF00D4FF44)),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00D4FF33)),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00D4FF33)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00D4FF)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL',
                style: TextStyle(
                    color: Color(0xFF00D4FF55),
                    fontSize: 11,
                    letterSpacing: 2)),
          ),
          TextButton(
            onPressed: () async {
              if (noteController.text.isNotEmpty) {
                await FridayDatabase.saveMemory(
                    type: 'note', content: noteController.text);
                Navigator.pop(context);
                _loadStats();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Memory saved, boss.',
                          style: TextStyle(fontFamily: 'monospace')),
                      backgroundColor: Color(0xFF0D0D1A),
                    ),
                  );
                }
              }
            },
            child: const Text('SAVE',
                style: TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 11,
                    letterSpacing: 2)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet({
    required String title,
    required List<String> items,
    required String emptyText,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Color(0xFF00D4FF),
                  fontSize: 12,
                  letterSpacing: 4,
                  fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Container(height: 1, color: const Color(0xFF00D4FF22)),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(emptyText,
                        style: const TextStyle(
                            color: Color(0xFF00D4FF44),
                            fontFamily: 'monospace')))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin:
                                const EdgeInsets.only(top: 6, right: 10),
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00D4FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(items[i],
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontFamily: 'monospace')),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _plasmaController.dispose();
    _llama.dispose();
    _locationTimer?.cancel();
    _connectivityTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('F.R.I.D.A.Y',
                      style: TextStyle(
                          color: Color(0xFF00D4FF),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 6,
                          fontFamily: 'monospace')),
                  Row(
                    children: [
                      Text(
                        _isOnline ? 'ONLINE' : 'OFFLINE',
                        style: TextStyle(
                            color: _isOnline
                                ? const Color(0xFF00FF88)
                                : Colors.white54,
                            fontSize: 10,
                            letterSpacing: 2,
                            fontFamily: 'monospace'),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isOnline
                              ? const Color(0xFF00FF88)
                              : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Loading
            if (_isLoading && !_modelReady) ...[
              LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                color: const Color(0xFF00D4FF),
                backgroundColor: const Color(0xFF00D4FF11),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF00D4FF88),
                        fontFamily: 'monospace',
                        fontSize: 12)),
              ),
              if (_downloadProgress > 0)
                Text(
                    '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF00D4FF),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace')),
            ],

            // Orb
            AnimatedBuilder(
              animation:
                  Listenable.merge([_pulseAnim, _plasmaAnim]),
              builder: (_, __) => CustomPaint(
                painter: OrbPainter(
                  pulse: _pulseAnim.value,
                  plasma: _plasmaAnim.value,
                ),
                size: const Size(170, 170),
              ),
            ),

            // Greeting
            Text(
              _modelReady ? _getGreeting() : 'Initializing...',
              style: const TextStyle(
                  color: Color(0xFF00D4FFCC),
                  fontSize: 13,
                  letterSpacing: 1,
                  fontFamily: 'monospace'),
            ),

            const SizedBox(height: 10),

            // Scan line
            Container(
              width: MediaQuery.of(context).size.width * 0.5,
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0xFF00D4FF),
                    Colors.transparent
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statChip('24%', 'TRAINED'),
                  _statChip('$_locationCount', 'LOCATIONS'),
                  _statChip('$_messageCount', 'MEMORIES'),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              color: const Color(0xFF00D4FF11),
            ),

            // Chat
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg['role'] == 'user';
                  return Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFF00D4FF)
                            : const Color(0xFF0D0D1A),
                        borderRadius: isUser
                            ? const BorderRadius.only(
                                topLeft: Radius.circular(14),
                                topRight: Radius.circular(14),
                                bottomLeft: Radius.circular(14),
                              )
                            : const BorderRadius.only(
                                topRight: Radius.circular(14),
                                bottomLeft: Radius.circular(14),
                                bottomRight: Radius.circular(14),
                              ),
                        border: isUser
                            ? null
                            : Border.all(
                                color: const Color(0xFF00D4FF22),
                                width: 1),
                      ),
                      child: msg['text']!.isEmpty && !isUser
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF00D4FF),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text('thinking...',
                                    style: TextStyle(
                                        color: Color(0xFF00D4FF),
                                        fontSize: 12,
                                        fontFamily: 'monospace')),
                              ],
                            )
                          : Text(msg['text']!,
                              style: TextStyle(
                                  color: isUser
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 13,
                                  fontFamily: 'monospace')),
                    ),
                  );
                },
              ),
            ),

            // Bottom bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: const BoxDecoration(
                color: Color(0xFF080810),
                border: Border(
                    top: BorderSide(color: Color(0xFF00D4FF11))),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D0D1A),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: const Color(0xFF00D4FF33),
                                width: 1),
                          ),
                          child: TextField(
                            controller: _controller,
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 13),
                            decoration: InputDecoration(
                              hintText: _modelReady
                                  ? 'Talk to Friday...'
                                  : 'Loading...',
                              hintStyle: const TextStyle(
                                  color: Color(0xFF00D4FF33),
                                  fontFamily: 'monospace',
                                  fontSize: 13),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 12),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00D4FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.send,
                              color: Colors.black, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _actionBtn('MEMORIES', _showMemories),
                      const SizedBox(width: 8),
                      _actionBtn('LOCATIONS', _showLocations),
                      const SizedBox(width: 8),
                      _actionBtn('+ NOTE', _showNoteDialog),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00D4FF22)),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Color(0xFF00D4FF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF00D4FF55),
                  fontSize: 9,
                  letterSpacing: 1,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF00D4FF22)),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFF00D4FF77),
                fontSize: 10,
                letterSpacing: 1,
                fontFamily: 'monospace')),
      ),
    );
  }
}