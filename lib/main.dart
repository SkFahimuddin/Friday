import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'location_service.dart';
import 'database.dart';

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
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  bool _modelReady = false;
  String _statusText = 'Loading AI model...';
  double _downloadProgress = 0;
  final LlamaController _llama = LlamaController();
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _initFriday();
    _initLocation();
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
      }

      setState(() => _statusText = 'Loading AI into memory...');
      await _llama.loadModel(
        modelPath: modelPath,
        threads: 4,
        contextSize: 2048,
      );

      setState(() {
        _modelReady = true;
        _isLoading = false;
        _messages.add({
          'role': 'friday',
          'text': 'Hello. I am Friday, your offline AI assistant. How can I help you?'
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

    // Save user message to DB
    await FridayDatabase.saveConversation(role: 'user', message: text);

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isLoading = true;
      _messages.add({'role': 'friday', 'text': ''});
    });
    _controller.clear();
    _scrollToBottom();

    try {
      // Build memory context
      final memoryContext = await FridayDatabase.buildMemoryContext();
      final fullPrompt = '<|system|>You are Friday, a helpful personal AI assistant. Here is context about the user:\n\n$memoryContext</s><|user|>$text</s><|assistant|>';

      String response = '';
      await for (final token in _llama.generate(
        prompt: fullPrompt,
        maxTokens: 256,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
      )) {
        response += token;
        setState(() {
          _messages[_messages.length - 1] = {'role': 'friday', 'text': response};
        });
        _scrollToBottom();
      }

      // Save Friday's response to DB
      await FridayDatabase.saveConversation(role: 'friday', message: response.trim());
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _messages[_messages.length - 1] = {'role': 'friday', 'text': 'Error: $e'};
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _llama.dispose();
    _locationTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
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
        actions: [
          IconButton(
            icon: const Icon(Icons.location_on, color: Color(0xFF00D4FF)),
            onPressed: () async {
              final summary = await LocationService.getLocationSummary();
              if (mounted) {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Location Log', style: TextStyle(color: Color(0xFF00D4FF))),
                    content: Text(summary, style: const TextStyle(color: Colors.white)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close', style: TextStyle(color: Color(0xFF00D4FF))),
                      )
                    ],
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.note_add, color: Color(0xFF00D4FF)),
            onPressed: () {
              final noteController = TextEditingController();
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('Add Memory', style: TextStyle(color: Color(0xFF00D4FF))),
                  content: TextField(
                    controller: noteController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'e.g. I had coffee at 9am...',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (noteController.text.isNotEmpty) {
                          await FridayDatabase.saveMemory(
                            type: 'note',
                            content: noteController.text,
                          );
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Memory saved!')),
                          );
                        }
                      },
                      child: const Text('Save', style: TextStyle(color: Color(0xFF00D4FF))),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading && !_modelReady)
            Column(
              children: [
                LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  color: const Color(0xFF00D4FF),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_statusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey)),
                ),
                if (_downloadProgress > 0)
                  Text('${(_downloadProgress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: Color(0xFF00D4FF),
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
              ],
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
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
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF00D4FF) : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: msg['text']!.isEmpty && !isUser
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00D4FF),
                            ),
                          )
                        : Text(msg['text']!,
                            style: TextStyle(
                                color: isUser ? Colors.black : Colors.white,
                                fontSize: 15)),
                  ),
                );
              },
            ),
          ),
          if (_isLoading && _modelReady)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Friday is thinking...',
                  style: TextStyle(color: Colors.grey)),
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
                      hintText: _modelReady ? 'Ask Friday anything...' : 'Loading AI...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
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