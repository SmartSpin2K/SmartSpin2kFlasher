import 'package:flutter/material.dart';

import '../theme.dart';

/// A console-style output widget with dark background and monospace font.
class ConsoleOutput extends StatefulWidget {
  final ScrollController? scrollController;

  const ConsoleOutput({super.key, this.scrollController});

  @override
  State<ConsoleOutput> createState() => ConsoleOutputState();
}

class ConsoleOutputState extends State<ConsoleOutput> {
  final List<ConsoleSpan> _spans = [];
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
  }

  @override
  void dispose() {
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void clear() {
    setState(() {
      _spans.clear();
    });
  }

  void appendText(String text, {Color? color}) {
    setState(() {
      // Parse ANSI codes for basic color support
      final stripped = _stripAnsi(text);
      _spans.add(ConsoleSpan(text: stripped, color: color));
    });
    _scrollToBottom();
  }

  String _stripAnsi(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 50),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      decoration: BoxDecoration(
        color: SS2KColors.consoleBg(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SS2KColors.border(brightness)),
      ),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          child: SelectableText.rich(
            TextSpan(
              children: _spans
                  .map(
                    (span) => TextSpan(
                      text: span.text,
                      style: TextStyle(
                        color: span.color ??
                            SS2KColors.consoleText(brightness),
                        fontFamily: 'Consolas, monospace',
                        fontSize: 13,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class ConsoleSpan {
  final String text;
  final Color? color;

  ConsoleSpan({required this.text, this.color});
}
