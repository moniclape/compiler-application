import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const Judge0MiniApp());
}

class Judge0MiniApp extends StatelessWidget {
  const Judge0MiniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mini Compiler',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: const CompilerPage(),
    );
  }
}

class CompilerPage extends StatefulWidget {
  const CompilerPage({super.key});

  @override
  State<CompilerPage> createState() => _CompilerPageState();
}

class _CompilerPageState extends State<CompilerPage> {
  final TextEditingController _codeController = TextEditingController(
    text: 'print("Hello, Judge0")',
  );
  final TextEditingController _stdinController = TextEditingController();
  String _output = '';
  bool _loading = false;

  //API change
  static const String judge0Base = 'https://judge0-ce.p.rapidapi.com';
  static const Map<String, String> extraHeaders = {
    'X-RapidAPI-Key': 'СЮДА ТВОЙ API JUDGE0 RAPIDAPI',
    'X-RapidAPI-Host': 'judge0-ce.p.rapidapi.com',
  };

  List<Map<String, dynamic>> _languages = [];
  int? _selectedLanguageId;

  @override
  void initState() {
    super.initState();
    _fetchLanguages();
  }

  Future<void> _fetchLanguages() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse('$judge0Base/languages');
      final resp = await http.get(uri, headers: extraHeaders);

      if (resp.statusCode == 200) {
        final List parsed = jsonDecode(resp.body) as List;
        _languages = parsed
            .map((e) => {'id': e['id'], 'name': e['name']})
            .toList();
        final py = _languages.firstWhere(
          (l) => (l['name'] as String).toLowerCase().contains('python 3'),
          orElse: () => _languages.isNotEmpty
              ? _languages.first
              : {'id': 109, 'name': 'Python 3'},
        );
        _selectedLanguageId = py['id'] as int;
      } else {
        _output = 'Failed to fetch languages: ${resp.statusCode}';
      }
    } catch (e) {
      _output = 'Error fetching languages: $e';
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _runCode() async {
    final code = _codeController.text;
    final stdin = _stdinController.text;
    if (_selectedLanguageId == null) {
      setState(() => _output = 'No language selected');
      return;
    }

    setState(() {
      _loading = true;
      _output = '';
    });

    try {
      final uri = Uri.parse(
        '$judge0Base/submissions?base64_encoded=true&wait=true',
      );

      final body = jsonEncode({
        'source_code': base64Encode(utf8.encode(code)),
        'language_id': _selectedLanguageId,
        'stdin': base64Encode(utf8.encode(stdin)),
      });

      final headers = {'Content-Type': 'application/json', ...extraHeaders};

      final resp = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;

        String decodeField(String key) {
          if (!data.containsKey(key) || data[key] == null) return '';
          try {
            return utf8.decode(base64Decode(data[key] as String));
          } catch (_) {
            return data[key].toString();
          }
        }

        final stdout = decodeField('stdout');
        final stderr = decodeField('stderr');
        final compileOutput = decodeField('compile_output');

        final buffer = StringBuffer();
        if (compileOutput.isNotEmpty)
          buffer.writeln('--- Compile output ---\n$compileOutput');
        if (stderr.isNotEmpty) buffer.writeln('--- Stderr ---\n$stderr');
        if (stdout.isNotEmpty) buffer.writeln('--- Output ---\n$stdout');

        setState(() => _output = buffer.toString().trim());
      } else {
        setState(
          () => _output =
              'Execution failed: HTTP ${resp.statusCode} - ${resp.body}',
        );
      }
    } catch (e) {
      setState(() => _output = 'Error running code: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mini Compiler'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              //Language picker + run button
              Row(
                children: [
                  Expanded(
                    child: _languages.isEmpty
                        ? const Text('Loading languages...')
                        : DropdownButton<int>(
                            isExpanded: true,
                            value: _selectedLanguageId,
                            items: _languages
                                .map(
                                  (l) => DropdownMenuItem<int>(
                                    value: l['id'] as int,
                                    child: Text(
                                      l['name'] as String,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedLanguageId = v),
                          ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _runCode,
                    icon: const Icon(Icons.play_arrow),
                    label: _loading
                        ? const Text('Running...')
                        : const Text('Run'),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              //Code editor (simple multiline TextField)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _codeController,
                    expands: true,
                    maxLines: null,
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Write your code here',
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              //Stdin input
              TextField(
                controller: _stdinController,
                decoration: const InputDecoration(
                  labelText: 'Stdin (optional)',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 3,
              ),

              const SizedBox(height: 8),

              //Output area
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: 80,
                  maxHeight: 240,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _output.isEmpty ? 'Output will appear here' : _output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
