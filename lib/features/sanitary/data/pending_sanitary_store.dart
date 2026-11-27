import 'package:sqflite/sqflite.dart';

import '../domain/upcoming_event.dart';

/// US-35: operaciones que se pueden crear sin conexion (US-11 registrar, US-13 programar una vacuna).
enum SanitaryOperation { register, schedule }

/// US-35: POST de creacion de un evento sanitario, con los valores exactos que viajan al backend. [date] ya va en el
/// formato del request (occurredAt `yyyy-MM-ddT00:00:00` o scheduledDate `yyyy-MM-dd`) para que cada reintento envie
/// el mismo cuerpo: con el mismo [clientRequestId] y otros datos el backend responderia 409.
class SanitaryRequest {
  const SanitaryRequest({
    required this.operation,
    required this.animalId,
    required this.type,
    required this.date,
    this.description,
    required this.clientRequestId,
  });

  final SanitaryOperation operation;
  final String animalId;
  final SanitaryEventType type;
  final String date;
  final String? description;
  final String clientRequestId;

  String get path => switch (operation) {
        SanitaryOperation.register => 'api/v1/animals/$animalId/sanitary-events',
        SanitaryOperation.schedule => 'api/v1/animals/$animalId/sanitary-events/scheduled',
      };

  Map<String, Object> get body => {
        'type': type.name.toUpperCase(),
        operation == SanitaryOperation.register ? 'occurredAt' : 'scheduledDate': date,
        'description': ?description,
        'clientRequestId': clientRequestId,
      };
}

/// PENDING = se enviara; FAILED = el backend la rechazo (400, 404, 409...) y no se reenvia sola. No hay SYNCING (quedaria
/// colgada si el sistema mata la app a mitad del envio) ni SYNCED (tras el exito la fila se borra).
enum PendingStatus { pending, failed }

/// US-35: [request] guardado en el dispositivo a la espera del backend, de un usuario ([userId], id de IAM de la sesion).
/// No es cache: son datos que el usuario aun no tiene en el servidor. No guarda token ni contrasena.
class PendingSanitaryOperation {
  const PendingSanitaryOperation({
    required this.request,
    required this.userId,
    required this.createdAt,
    this.status = PendingStatus.pending,
    this.lastError,
  });

  final SanitaryRequest request;
  final String userId;
  final DateTime createdAt;
  final PendingStatus status;

  /// Ultimo error: message del backend, `HTTP <codigo>` o `CONNECTION`; null si no se intento o no fallo.
  final String? lastError;

  String get clientRequestId => request.clientRequestId;
}

/// US-35: cola offline en SQLite (`gethics.db`). Cada consulta filtra por usuario: las operaciones de uno nunca se
/// leen ni se envian con la sesion de otro.
///
/// Migraciones: la tabla guarda datos sin enviar, asi que una version futura debe migrar con ALTER/INSERT en
/// [_onUpgrade]; nunca borrar la base ni la tabla.
class PendingSanitaryStore {
  PendingSanitaryStore(this._db);

  static const _table = 'pending_sanitary_operations';
  static const _version = 1;

  final Database _db;

  /// [factory] y [path] solo para pruebas (sqflite_common_ffi, base en memoria o temporal).
  static Future<PendingSanitaryStore> open({DatabaseFactory? factory, String? path}) async {
    final databases = factory ?? databaseFactory;
    final file = path ?? '${await databases.getDatabasesPath()}/gethics.db';
    final db = await databases.openDatabase(
      file,
      options: OpenDatabaseOptions(version: _version, onCreate: _onCreate, onUpgrade: _onUpgrade),
    );
    return PendingSanitaryStore(db);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_table (
        client_request_id TEXT PRIMARY KEY NOT NULL,
        user_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        animal_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        date TEXT NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'FAILED')),
        last_error TEXT
      )''');
    await db.execute('CREATE INDEX ${_table}_user ON $_table (user_id, status, created_at)');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 es la primera version. Las siguientes migran aqui sin perder filas (ver la documentacion de la clase).
  }

  /// Falla si el clientRequestId ya existe: un id nunca se reutiliza para otra operacion.
  Future<void> insert(PendingSanitaryOperation operation) => _db.insert(_table, {
        'client_request_id': operation.clientRequestId,
        'user_id': operation.userId,
        'operation': operation.request.operation.name.toUpperCase(),
        'animal_id': operation.request.animalId,
        'event_type': operation.request.type.name.toUpperCase(),
        'date': operation.request.date,
        'description': operation.request.description,
        'created_at': operation.createdAt.millisecondsSinceEpoch,
        'status': _statusName(operation.status),
        'last_error': operation.lastError,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

  /// PENDING del usuario, en orden de creacion (rowid desempata las del mismo milisegundo).
  Future<List<PendingSanitaryOperation>> pending(String userId) => _query(userId, onlyPending: true);

  /// PENDING y FAILED del usuario, en orden de creacion (para mostrarlas o reintentarlas, US-40).
  Future<List<PendingSanitaryOperation>> all(String userId) => _query(userId, onlyPending: false);

  Future<List<PendingSanitaryOperation>> _query(String userId, {required bool onlyPending}) async {
    final rows = await _db.query(
      _table,
      where: onlyPending ? "user_id = ? AND status = 'PENDING'" : 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at, rowid',
    );
    return rows.map(_fromRow).toList();
  }

  Future<PendingSanitaryOperation?> find(String clientRequestId) async {
    final rows = await _db.query(_table, where: 'client_request_id = ?', whereArgs: [clientRequestId]);
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<void> delete(String clientRequestId) =>
      _db.delete(_table, where: 'client_request_id = ?', whereArgs: [clientRequestId]);

  /// Rechazo definitivo: se conserva con el error para no perder el dato en silencio y no se reenvia sola.
  Future<void> markFailed(String clientRequestId, String error) => _update(clientRequestId, PendingStatus.failed, error);

  /// Error transitorio: sigue PENDING y se guarda el ultimo error.
  Future<void> recordError(String clientRequestId, String error) => _update(clientRequestId, PendingStatus.pending, error);

  /// Reintento manual de una FAILED del usuario (US-40): vuelve a PENDING con el MISMO clientRequestId. Devuelve false si
  /// no existe o es de otro usuario.
  Future<bool> retry(String userId, String clientRequestId) async {
    final count = await _db.update(_table, {'status': 'PENDING'},
        where: 'client_request_id = ? AND user_id = ?', whereArgs: [clientRequestId, userId]);
    return count > 0;
  }

  Future<void> _update(String clientRequestId, PendingStatus status, String error) => _db.update(
        _table,
        {'status': _statusName(status), 'last_error': error},
        where: 'client_request_id = ?',
        whereArgs: [clientRequestId],
      );

  Future<void> close() => _db.close();

  static String _statusName(PendingStatus status) => status.name.toUpperCase();

  static PendingSanitaryOperation _fromRow(Map<String, Object?> row) => PendingSanitaryOperation(
        request: SanitaryRequest(
          operation: SanitaryOperation.values.byName((row['operation'] as String).toLowerCase()),
          animalId: row['animal_id'] as String,
          type: SanitaryEventType.fromName(row['event_type'] as String),
          date: row['date'] as String,
          description: row['description'] as String?,
          clientRequestId: row['client_request_id'] as String,
        ),
        userId: row['user_id'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        status: row['status'] == 'FAILED' ? PendingStatus.failed : PendingStatus.pending,
        lastError: row['last_error'] as String?,
      );
}
