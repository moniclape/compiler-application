import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/ruby.dart';
import 'package:highlight/languages/bash.dart';

import 'package:flutter_highlight/themes/monokai-sublime.dart';

final Map<String, dynamic> highlightMap = {
  'python': python,
  'javascript': javascript,
  'dart': dart,
  'c++': cpp,
  'java': java,
  'rust': rust,
  'ruby': ruby,
  'bash': bash,
};

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage("assets/background.png"),
          fit: BoxFit.cover,
        ),
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Mini Compiler',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          scaffoldBackgroundColor: Colors.transparent,
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
          ),
          dropdownMenuTheme: const DropdownMenuThemeData(
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
        home: const CompilerPage(),
      ),
    );
  }
}

class CompilerPage extends StatefulWidget {
  const CompilerPage({super.key});

  @override
  State<CompilerPage> createState() => _CompilerPageState();
}

class _CompilerPageState extends State<CompilerPage> {
  late CodeController _codeController;
  final TextEditingController _stdinController = TextEditingController();

  String _output = '';
  bool _loading = false;

  static const String judge0Base = 'https://judge0-ce.p.rapidapi.com';
  static const Map<String, String> extraHeaders = {
    'X-RapidAPI-Key': '77380eafebmshc828cbfd3b92d2cp1a6692jsn0ab874ce6bf6',
    'X-RapidAPI-Host': 'judge0-ce.p.rapidapi.com',
  };

  List<Map<String, dynamic>> _languages = [];
  int? _selectedLanguageId;

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(text: 'print("Hello, World!")');
    _fetchLanguages();
  }

  Future<void> _fetchLanguages() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse('$judge0Base/languages');
      final resp = await http.get(uri, headers: extraHeaders);
      if (resp.statusCode == 200) {
        final List parsed = jsonDecode(resp.body) as List;
        final supportedNames = [
          'python',
          'javascript',
          'dart',
          'c++',
          'java',
          'rust',
          'ruby',
          'bash',
        ];
        _languages = parsed
            .map((e) => {'id': e['id'], 'name': e['name'] as String})
            .where((l) {
              final name = l['name'].toLowerCase();
              final cleaned = name.replaceAll(RegExp(r'[^a-z\+\#]'), ' ');

              return supportedNames.any(
                (supported) => cleaned.split(' ').contains(supported),
              );
            })
            .toList();
        _languages.sort((a, b) {
          final aName = a['name'].toLowerCase();
          final bName = b['name'].toLowerCase();
          return supportedNames
              .indexOf(aName)
              .compareTo(supportedNames.indexOf(bName));
        });
        if (_languages.isNotEmpty) {
          _selectedLanguageId = _languages.firstWhere(
            (l) => (l['name'] as String).toLowerCase().contains('python'),
            orElse: () => _languages[0],
          )['id'];
        } else {
          _selectedLanguageId = null;
          _output = 'No supported languages found';
        }
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
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = jsonDecode(resp.body);
        String decodeField(String key) {
          if (!data.containsKey(key) || data[key] == null) return '';
          try {
            return utf8.decode(base64Decode(data[key]));
          } catch (_) {
            return data[key].toString();
          }
        }

        final stdout = decodeField('stdout');
        final stderr = decodeField('stderr');
        final compileOutput = decodeField('compile_output');
        final buf = StringBuffer();
        if (compileOutput.isNotEmpty)
          buf.writeln('--- Compile output ---\n$compileOutput');
        if (stderr.isNotEmpty) buf.writeln('--- Stderr ---\n$stderr');
        if (stdout.isNotEmpty) buf.writeln('--- Output ---\n$stdout');
        setState(() => _output = buf.toString());
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
        backgroundColor: Colors.transparent,
        foregroundColor: const Color.fromARGB(255, 255, 255, 255),
        title: const Text('Compiler'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _languages.isEmpty
                        ? const Text(
                            'Loading languages...',
                            style: TextStyle(color: Colors.white),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white, // ← БЕЛЫЙ ФОН
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: _selectedLanguageId,

                              dropdownColor: Colors.white, // ← БЕЛЫЙ СПИСОК
                              style: const TextStyle(
                                color: Colors.black, // ← ЧЁРНЫЙ ТЕКСТ
                                fontSize: 16,
                              ),
                              iconEnabledColor:
                                  Colors.black, // ← ЧЁРНАЯ СТРЕЛКА
                              underline:
                                  const SizedBox(), // ← убрать нижнюю линию

                              items: _languages
                                  .map(
                                    (l) => DropdownMenuItem<int>(
                                      value: l['id'],
                                      child: Text(
                                        l['name'],
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),

                              onChanged: (v) {
                                setState(() {
                                  _selectedLanguageId = v;

                                  final fullName = _languages
                                      .firstWhere((e) => e['id'] == v)['name']
                                      .toString()
                                      .toLowerCase();

                                  final cleaned = fullName.replaceAll(
                                    RegExp(r'[^a-z\+\#]'),
                                    ' ',
                                  );

                                  final supported = highlightMap.keys
                                      .firstWhere(
                                        (s) => cleaned.split(' ').contains(s),
                                        orElse: () => 'python',
                                      );

                                  _codeController.language =
                                      highlightMap[supported];
                                });
                              },
                            ),
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
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.black,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: CodeTheme(
                    data: CodeThemeData(styles: monokaiSublimeTheme),
                    child: CodeField(
                      controller: _codeController,
                      textStyle: const TextStyle(
                        fontFamily: 'SourceCode',
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _stdinController,
                decoration: InputDecoration(
                  labelText: 'Stdin (optional)',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.9),
                ),

                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: 80,
                  maxHeight: 240,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black,
                ),
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  _output.isEmpty ? 'Output will appear here' : _output,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.white,
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
