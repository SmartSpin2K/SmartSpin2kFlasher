import 'dart:async';

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
  static const _maxCharacters = 250000;
  static const _maxSpans = 2000;
  static const _maxPendingCharacters = 50000;
  static const _maxPendingSpans = 500;

  final List<ConsoleSpan> _spans = [];
  final List<ConsoleSpan> _pendingSpans = [];
  late final ScrollController _scrollController;
  Timer? _flushTimer;
  int _characterCount = 0;
  int _pendingCharacterCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void clear() {
    _flushTimer?.cancel();
    _flushTimer = null;
    setState(() {
      _spans.clear();
      _pendingSpans.clear();
      _characterCount = 0;
      _pendingCharacterCount = 0;
    });
  }

  void appendText(String text, {Color? color}) {
    final stripped = _stripAnsi(text);
    if (stripped.isEmpty) return;

    // Log sources can be very chatty. Batch visual updates while keeping a
    // deliberately bounded recent history; full history belongs in a file.
    _addToBuffer(
      _pendingSpans,
      stripped,
      color,
      maxCharacters: _maxPendingCharacters,
      maxSpans: _maxPendingSpans,
      isPending: true,
    );
    _flushTimer ??= Timer(const Duration(milliseconds: 75), _flushPending);
  }

  void _flushPending() {
    _flushTimer = null;
    if (!mounted || _pendingSpans.isEmpty) return;

    setState(() {
      for (final span in _pendingSpans) {
        _addToBuffer(
          _spans,
          span.text,
          span.color,
          maxCharacters: _maxCharacters,
          maxSpans: _maxSpans,
          isPending: false,
        );
      }
      _pendingSpans.clear();
      _pendingCharacterCount = 0;
    });
    _scrollToBottom();
  }

  void _addToBuffer(
    List<ConsoleSpan> buffer,
    String text,
    Color? color, {
    required int maxCharacters,
    required int maxSpans,
    required bool isPending,
  }) {
    var value = text;
    if (value.length > maxCharacters) {
      value = value.substring(value.length - maxCharacters);
    }

    if (buffer.isNotEmpty && buffer.last.color == color) {
      buffer.last.text += value;
    } else {
      buffer.add(ConsoleSpan(text: value, color: color));
    }

    if (isPending) {
      _pendingCharacterCount += value.length;
    } else {
      _characterCount += value.length;
    }
    _trimBuffer(buffer, maxCharacters, maxSpans, isPending: isPending);
  }

  void _trimBuffer(
    List<ConsoleSpan> buffer,
    int maxCharacters,
    int maxSpans, {
    required bool isPending,
  }) {
    var characterCount = isPending ? _pendingCharacterCount : _characterCount;
    while (buffer.isNotEmpty &&
        (characterCount > maxCharacters || buffer.length > maxSpans)) {
      final first = buffer.first;
      final excess = characterCount - maxCharacters;
      if (excess <= 0 || first.text.length <= excess) {
        characterCount -= first.text.length;
        buffer.removeAt(0);
      } else {
        first.text = first.text.substring(excess);
        characterCount -= excess;
      }
    }
    if (isPending) {
      _pendingCharacterCount = characterCount;
    } else {
      _characterCount = characterCount;
    }
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
                        color: span.color ?? SS2KColors.consoleText(brightness),
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
  String text;
  final Color? color;

  ConsoleSpan({required this.text, this.color});
}
