/// A small, non-executable expression language for notification filters.
/// Notification data never becomes code. There are no calls or property access.
class NotificationCondition {
  NotificationCondition(String expression)
    : _root = _Parser(expression.trim().isEmpty ? 'true' : expression).parse();

  final _Node _root;
  bool matches(Map<String, Object?> values) => _root(values) == true;

  static const fields = {
    'package',
    'appLabel',
    'title',
    'text',
    'lines',
    'category',
    'ongoing',
  };

  /// Lossless recognition of expressions representable by the basic form.
  static Map<String, String>? formValues(String expression) {
    if (expression.trim().isEmpty) return {};
    try {
      final tokens = _Parser._lex(expression);
      final values = <String, String>{};
      var i = 0;
      while (i < tokens.length - 1) {
        if (i + 2 >= tokens.length) return null;
        final a = tokens[i], op = tokens[i + 1], b = tokens[i + 2];
        if (a.kind == 'field' &&
            a.value == 'package' &&
            op.kind == '==' &&
            b.kind == 'literal' &&
            b.value is String &&
            !values.containsKey('package')) {
          values['package'] = b.value! as String;
        } else if (a.kind == 'literal' &&
            a.value is String &&
            op.kind == 'in' &&
            b.kind == 'field' &&
            {'title', 'text'}.contains(b.value) &&
            !values.containsKey(b.value)) {
          values[b.value! as String] = a.value! as String;
        } else {
          return null;
        }
        i += 3;
        if (tokens[i].kind == 'eof') break;
        if (tokens[i++].kind != 'and') return null;
      }
      return values;
    } on FormatException {
      return null;
    }
  }

  static String form({
    String package = '',
    String title = '',
    String text = '',
  }) {
    String quote(String value) =>
        '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
    return [
      if (package.isNotEmpty) 'package == ${quote(package)}',
      if (title.isNotEmpty) '${quote(title)} in title',
      if (text.isNotEmpty) '${quote(text)} in text',
    ].join(' and ');
  }
}

typedef _Node = Object? Function(Map<String, Object?> values);

class _Token {
  const _Token(this.kind, this.value);
  final String kind;
  final Object? value;
}

class _Parser {
  _Parser(String source) : tokens = _lex(source);
  final List<_Token> tokens;
  int position = 0;
  int depth = 0;
  _Token get current => tokens[position];
  bool take(String kind) {
    if (current.kind != kind) return false;
    position++;
    return true;
  }

  void require(String kind) {
    if (!take(kind)) throw FormatException('Expected $kind');
  }

  _Node parse() {
    final node = expression();
    require('eof');
    return node;
  }

  _Node expression() {
    if (++depth > 32) throw const FormatException('Condition is too deep');
    var node = conjunction();
    while (take('or')) {
      final left = node;
      final right = conjunction();
      node = (v) => left(v) == true || right(v) == true;
    }
    depth--;
    return node;
  }

  _Node conjunction() {
    var node = comparison();
    while (take('and')) {
      final left = node;
      final right = comparison();
      node = (v) => left(v) == true && right(v) == true;
    }
    return node;
  }

  _Node comparison() {
    if (take('not')) {
      if (++depth > 32) throw const FormatException('Condition is too deep');
      final operand = comparison();
      depth--;
      return (v) => operand(v) != true;
    }
    final left = atom();
    var operator = current.kind;
    if (!{'==', '!=', 'in', 'not'}.contains(operator)) return left;
    position++;
    if (operator == 'not') {
      require('in');
      operator = 'not in';
    }
    final right = atom();
    return (v) {
      final a = left(v);
      final b = right(v);
      if (operator == '==') return a == b;
      if (operator == '!=') return a != b;
      final contains = b is String && a is String
          ? b.contains(a)
          : b is List && b.contains(a);
      return operator == 'not in' ? !contains : contains;
    };
  }

  _Node atom() {
    if (take('(')) {
      final node = expression();
      require(')');
      return node;
    }
    if (take('[')) {
      final items = <_Node>[];
      if (!take(']')) {
        do {
          if (current.kind != 'literal') {
            throw const FormatException('Expected literal');
          }
          items.add(atom());
        } while (take(','));
        require(']');
      }
      return (v) => items.map((n) => n(v)).toList();
    }
    final token = current;
    if (take('literal')) return (_) => token.value;
    if (take('field')) {
      final name = token.value! as String;
      return (v) =>
          v[name] ??
          (name == 'lines'
              ? const <String>[]
              : name == 'ongoing'
              ? false
              : '');
    }
    throw const FormatException('Expected notification field or literal');
  }

  static List<_Token> _lex(String source) {
    if (source.length > 4096) {
      throw const FormatException('Condition is too long');
    }
    final result = <_Token>[];
    var i = 0;
    while (i < source.length) {
      final c = source[i];
      if (RegExp(r'\s').hasMatch(c)) {
        i++;
        continue;
      }
      if (c == '"' || c == "'") {
        final quote = c;
        final value = StringBuffer();
        i++;
        var closed = false;
        while (i < source.length) {
          var next = source[i++];
          if (next == quote) {
            closed = true;
            break;
          }
          if (next == '\\') {
            if (i == source.length) {
              throw const FormatException('Invalid escape');
            }
            next = source[i++];
            next = switch (next) {
              'n' => '\n',
              'r' => '\r',
              't' => '\t',
              '\\' => '\\',
              '"' => '"',
              "'" => "'",
              _ => throw const FormatException('Invalid escape'),
            };
          }
          value.write(next);
        }
        if (!closed) throw const FormatException('Unclosed string');
        result.add(_Token('literal', value.toString()));
      } else if (i + 1 < source.length &&
          {'==', '!='}.contains(source.substring(i, i + 2))) {
        result.add(_Token(source.substring(i, i + 2), null));
        i += 2;
      } else if ('()[],'.contains(c)) {
        result.add(_Token(c, null));
        i++;
      } else {
        final match = RegExp(
          r'^[A-Za-z_][A-Za-z_0-9]*',
        ).firstMatch(source.substring(i));
        if (match == null) {
          throw const FormatException('Invalid condition character');
        }
        final word = match[0]!;
        i += word.length;
        if (word == 'true' || word == 'false') {
          result.add(_Token('literal', word == 'true'));
        } else if ({'and', 'or', 'not', 'in'}.contains(word)) {
          result.add(_Token(word, null));
        } else if (NotificationCondition.fields.contains(word)) {
          result.add(_Token('field', word));
        } else {
          throw FormatException('Unknown field: $word');
        }
      }
      if (result.length > 1024) {
        throw const FormatException('Too many condition tokens');
      }
    }
    return [...result, const _Token('eof', null)];
  }
}
