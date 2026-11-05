import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as io;
import 'package:tako_den/tako_den.dart';

const _usage =
    '''
Tako Den $serverVersion

Usage:
  tako-den [serve]                     Start the server.
  tako-den user add <name> [--admin]   Add a user (password from TAKO_PASSWORD or stdin).
  tako-den user passwd <name>          Set a user's password.
  tako-den backup <file>               Write a consistent copy of the database.

Configuration: tako-den.yaml (or TAKO_CONFIG) and TAKO_* environment
variables. See tako-den.example.yaml.''';

Future<void> main(List<String> args) async {
  try {
    await _run(args);
  } on Object {
    // Configuration parser errors can include a line containing a secret.
    stderr.writeln(
      'Command failed. Check the configuration and data-directory permissions.',
    );
    exitCode = 1;
  }
}

Future<void> _run(List<String> args) async {
  final config = DenConfig.load();
  Directory(config.dataDir).createSync(recursive: true);
  final store = Store.open(p.join(config.dataDir, 'tako-den.db'));

  final command = args.isEmpty ? 'serve' : args.first;
  try {
    switch (command) {
      case 'serve':
        await _serve(config, store);
        return;
      case 'user' when args.length >= 3 && args[1] == 'add':
        final user = store.createUser(
          args[2],
          _password(),
          isAdmin: args.contains('--admin'),
        );
        stdout.writeln('Added ${user.username}.');
      case 'user' when args.length >= 3 && args[1] == 'passwd':
        store.setPassword(args[2], _password());
        stdout.writeln('Password changed.');
      case 'backup' when args.length == 2:
        store.db.execute('VACUUM INTO ?', [args[1]]);
        stdout.writeln('Wrote ${args[1]}.');
      default:
        stdout.writeln(_usage);
        exitCode = 64;
    }
  } on StoreException catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  }
  store.close();
}

Future<void> _serve(DenConfig config, Store store) async {
  store.pruneTombstones();

  final server = DenServer(
    config: config,
    store: store,
    blobDir: p.join(config.dataDir, 'blobs'),
    secrets: Secrets.load(config.dataDir, encodedKey: config.secretKey),
  );
  if (server.setupToken case final token?) {
    final url = config.publicUrl ?? 'http://localhost:${config.port}';
    stdout.writeln('Open $url/setup?token=$token to create the administrator.');
  }
  final HttpServer http;
  try {
    http = await io.serve(server.handler, config.host, config.port);
  } on SocketException catch (e) {
    stderr.writeln(
      'Cannot listen on ${config.host}:${config.port} (${e.osError?.errorCode}). '
      'Is another program using it? Set TAKO_PORT to choose another port.',
    );
    exitCode = 69;
    await server.close();
    return;
  }
  stdout.writeln(
    'Tako Den $serverVersion on http://${config.host}:${config.port}',
  );
  stdout.writeln(
    'Enabled shared providers: ${server.providers.list().where((provider) => provider.enabled).length}.',
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Stopping.');
    await http.close(force: true);
    await server.close();
    store.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}

String _password() {
  final fromEnv = Platform.environment['TAKO_PASSWORD'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  stdout.write('Password: ');
  if (stdin.hasTerminal) stdin.echoMode = false;
  final password = stdin.readLineSync() ?? '';
  if (stdin.hasTerminal) stdin.echoMode = true;
  stdout.writeln();
  return password;
}
