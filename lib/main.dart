import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

void main() {
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
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  bool _modelReady = false;
  String _statusText = 'Checking for AI model...';
  double _downloadProgress = 0;
  String _modelPath = '';

  @override
  void initState() {
    super.initState();
    _initFriday();
  }

  Future<void> _initFriday() async {
    setState(() => _isLoading = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      _modelPath = '${dir.path}/tinyllama.gguf';
      final file = File(_modelPath);

      if (!await file.exists()) {
        setState(() => _statusText = 'Downloading AI model (637MB)...\nThis only happens once. Please wait.');
        const url = 'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';
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
        setState(() => _statusText = 'Download complete!');
      }

      setState(() {
        _modelReady = true;
        _isLoading = false;
        _messages.add({
          'role': 'friday',
          'text': 'Hello. I am Friday. Model is ready at: $_modelPath\n\nAI inference will be connected next step.'
        });
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusText = 'Error: $e';
        _messages.add({'role': 'friday', 'text': 'Error: $e'});
      });
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _messages.add({'role': 'friday', 'text': 'Model downloaded ✅ AI responses coming next step!'});
    });
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFF00D4FF)),
            SizedBox(width: 8),
            Text('FRIDAY', style: TextStyle(
              color: Color(0xFF00D4FF),
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            )),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_isLoading)
            Column(
              children: [
                LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  color: const Color(0xFF00D4FF),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                if (_downloadProgress > 0)
                  Text(
                    '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 24, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF00D4FF) : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      msg['text']!,
                      style: TextStyle(
                        color: isUser ? Colors.black : Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF111111),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _modelReady ? 'Ask Friday anything...' : 'Please wait...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF00D4FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send, color: Colors.black, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}