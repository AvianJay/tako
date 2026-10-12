// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ConversationRecordsTable extends ConversationRecords
    with TableInfo<$ConversationRecordsTable, ConversationRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, data, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversation_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConversationRecordsTable createAlias(String alias) {
    return $ConversationRecordsTable(attachedDatabase, alias);
  }
}

class ConversationRecord extends DataClass
    implements Insertable<ConversationRecord> {
  final String id;
  final String data;
  final DateTime updatedAt;
  const ConversationRecord({
    required this.id,
    required this.data,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['data'] = Variable<String>(data);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConversationRecordsCompanion toCompanion(bool nullToAbsent) {
    return ConversationRecordsCompanion(
      id: Value(id),
      data: Value(data),
      updatedAt: Value(updatedAt),
    );
  }

  factory ConversationRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationRecord(
      id: serializer.fromJson<String>(json['id']),
      data: serializer.fromJson<String>(json['data']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'data': serializer.toJson<String>(data),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ConversationRecord copyWith({
    String? id,
    String? data,
    DateTime? updatedAt,
  }) => ConversationRecord(
    id: id ?? this.id,
    data: data ?? this.data,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ConversationRecord copyWithCompanion(ConversationRecordsCompanion data) {
    return ConversationRecord(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationRecord(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, data, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationRecord &&
          other.id == this.id &&
          other.data == this.data &&
          other.updatedAt == this.updatedAt);
}

class ConversationRecordsCompanion extends UpdateCompanion<ConversationRecord> {
  final Value<String> id;
  final Value<String> data;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ConversationRecordsCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationRecordsCompanion.insert({
    required String id,
    required String data,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       data = Value(data),
       updatedAt = Value(updatedAt);
  static Insertable<ConversationRecord> custom({
    Expression<String>? id,
    Expression<String>? data,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? data,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ConversationRecordsCompanion(
      id: id ?? this.id,
      data: data ?? this.data,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationRecordsCompanion(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageRecordsTable extends MessageRecords
    with TableInfo<$MessageRecordsTable, MessageRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversation_records (id)',
    ),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    parentId,
    status,
    createdAt,
    data,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessageRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  $MessageRecordsTable createAlias(String alias) {
    return $MessageRecordsTable(attachedDatabase, alias);
  }
}

class MessageRecord extends DataClass implements Insertable<MessageRecord> {
  final String id;
  final String conversationId;
  final String? parentId;
  final String status;
  final DateTime createdAt;
  final String data;
  const MessageRecord({
    required this.id,
    required this.conversationId,
    this.parentId,
    required this.status,
    required this.createdAt,
    required this.data,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['data'] = Variable<String>(data);
    return map;
  }

  MessageRecordsCompanion toCompanion(bool nullToAbsent) {
    return MessageRecordsCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      status: Value(status),
      createdAt: Value(createdAt),
      data: Value(data),
    );
  }

  factory MessageRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRecord(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'parentId': serializer.toJson<String?>(parentId),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'data': serializer.toJson<String>(data),
    };
  }

  MessageRecord copyWith({
    String? id,
    String? conversationId,
    Value<String?> parentId = const Value.absent(),
    String? status,
    DateTime? createdAt,
    String? data,
  }) => MessageRecord(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    parentId: parentId.present ? parentId.value : this.parentId,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    data: data ?? this.data,
  );
  MessageRecord copyWithCompanion(MessageRecordsCompanion data) {
    return MessageRecord(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRecord(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('parentId: $parentId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, conversationId, parentId, status, createdAt, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRecord &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.parentId == this.parentId &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.data == this.data);
}

class MessageRecordsCompanion extends UpdateCompanion<MessageRecord> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String?> parentId;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<String> data;
  final Value<int> rowid;
  const MessageRecordsCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.data = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageRecordsCompanion.insert({
    required String id,
    required String conversationId,
    this.parentId = const Value.absent(),
    required String status,
    required DateTime createdAt,
    required String data,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       status = Value(status),
       createdAt = Value(createdAt),
       data = Value(data);
  static Insertable<MessageRecord> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? parentId,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<String>? data,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (parentId != null) 'parent_id': parentId,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (data != null) 'data': data,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String?>? parentId,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<String>? data,
    Value<int>? rowid,
  }) {
    return MessageRecordsCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      parentId: parentId ?? this.parentId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      data: data ?? this.data,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageRecordsCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('parentId: $parentId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('data: $data, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProviderRecordsTable extends ProviderRecords
    with TableInfo<$ProviderRecordsTable, ProviderRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provider_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProviderRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProviderRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProviderRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  $ProviderRecordsTable createAlias(String alias) {
    return $ProviderRecordsTable(attachedDatabase, alias);
  }
}

class ProviderRecord extends DataClass implements Insertable<ProviderRecord> {
  final String id;
  final String data;
  const ProviderRecord({required this.id, required this.data});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['data'] = Variable<String>(data);
    return map;
  }

  ProviderRecordsCompanion toCompanion(bool nullToAbsent) {
    return ProviderRecordsCompanion(id: Value(id), data: Value(data));
  }

  factory ProviderRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProviderRecord(
      id: serializer.fromJson<String>(json['id']),
      data: serializer.fromJson<String>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'data': serializer.toJson<String>(data),
    };
  }

  ProviderRecord copyWith({String? id, String? data}) =>
      ProviderRecord(id: id ?? this.id, data: data ?? this.data);
  ProviderRecord copyWithCompanion(ProviderRecordsCompanion data) {
    return ProviderRecord(
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProviderRecord(')
          ..write('id: $id, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, data);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProviderRecord &&
          other.id == this.id &&
          other.data == this.data);
}

class ProviderRecordsCompanion extends UpdateCompanion<ProviderRecord> {
  final Value<String> id;
  final Value<String> data;
  final Value<int> rowid;
  const ProviderRecordsCompanion({
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProviderRecordsCompanion.insert({
    required String id,
    required String data,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       data = Value(data);
  static Insertable<ProviderRecord> custom({
    Expression<String>? id,
    Expression<String>? data,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProviderRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? data,
    Value<int>? rowid,
  }) {
    return ProviderRecordsCompanion(
      id: id ?? this.id,
      data: data ?? this.data,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProviderRecordsCompanion(')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingRecordsTable extends SettingRecords
    with TableInfo<$SettingRecordsTable, SettingRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'setting_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRecord(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingRecordsTable createAlias(String alias) {
    return $SettingRecordsTable(attachedDatabase, alias);
  }
}

class SettingRecord extends DataClass implements Insertable<SettingRecord> {
  final String key;
  final String value;
  const SettingRecord({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingRecordsCompanion toCompanion(bool nullToAbsent) {
    return SettingRecordsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRecord(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRecord copyWith({String? key, String? value}) =>
      SettingRecord(key: key ?? this.key, value: value ?? this.value);
  SettingRecord copyWithCompanion(SettingRecordsCompanion data) {
    return SettingRecord(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRecord(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRecord &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingRecordsCompanion extends UpdateCompanion<SettingRecord> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingRecordsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingRecordsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRecord> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingRecordsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingRecordsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingRecordsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuditRecordsTable extends AuditRecords
    with TableInfo<$AuditRecordsTable, AuditRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toolCallIdMeta = const VerificationMeta(
    'toolCallId',
  );
  @override
  late final GeneratedColumn<String> toolCallId = GeneratedColumn<String>(
    'tool_call_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toolNameMeta = const VerificationMeta(
    'toolName',
  );
  @override
  late final GeneratedColumn<String> toolName = GeneratedColumn<String>(
    'tool_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _argumentsMeta = const VerificationMeta(
    'arguments',
  );
  @override
  late final GeneratedColumn<String> arguments = GeneratedColumn<String>(
    'arguments',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _riskMeta = const VerificationMeta('risk');
  @override
  late final GeneratedColumn<String> risk = GeneratedColumn<String>(
    'risk',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decisionMeta = const VerificationMeta(
    'decision',
  );
  @override
  late final GeneratedColumn<String> decision = GeneratedColumn<String>(
    'decision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resultSummaryMeta = const VerificationMeta(
    'resultSummary',
  );
  @override
  late final GeneratedColumn<String> resultSummary = GeneratedColumn<String>(
    'result_summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isErrorMeta = const VerificationMeta(
    'isError',
  );
  @override
  late final GeneratedColumn<bool> isError = GeneratedColumn<bool>(
    'is_error',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_error" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    messageId,
    toolCallId,
    toolName,
    arguments,
    risk,
    decision,
    resultSummary,
    isError,
    startedAt,
    finishedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('tool_call_id')) {
      context.handle(
        _toolCallIdMeta,
        toolCallId.isAcceptableOrUnknown(
          data['tool_call_id']!,
          _toolCallIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_toolCallIdMeta);
    }
    if (data.containsKey('tool_name')) {
      context.handle(
        _toolNameMeta,
        toolName.isAcceptableOrUnknown(data['tool_name']!, _toolNameMeta),
      );
    } else if (isInserting) {
      context.missing(_toolNameMeta);
    }
    if (data.containsKey('arguments')) {
      context.handle(
        _argumentsMeta,
        arguments.isAcceptableOrUnknown(data['arguments']!, _argumentsMeta),
      );
    } else if (isInserting) {
      context.missing(_argumentsMeta);
    }
    if (data.containsKey('risk')) {
      context.handle(
        _riskMeta,
        risk.isAcceptableOrUnknown(data['risk']!, _riskMeta),
      );
    } else if (isInserting) {
      context.missing(_riskMeta);
    }
    if (data.containsKey('decision')) {
      context.handle(
        _decisionMeta,
        decision.isAcceptableOrUnknown(data['decision']!, _decisionMeta),
      );
    } else if (isInserting) {
      context.missing(_decisionMeta);
    }
    if (data.containsKey('result_summary')) {
      context.handle(
        _resultSummaryMeta,
        resultSummary.isAcceptableOrUnknown(
          data['result_summary']!,
          _resultSummaryMeta,
        ),
      );
    }
    if (data.containsKey('is_error')) {
      context.handle(
        _isErrorMeta,
        isError.isAcceptableOrUnknown(data['is_error']!, _isErrorMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      toolCallId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_call_id'],
      )!,
      toolName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_name'],
      )!,
      arguments: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}arguments'],
      )!,
      risk: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}risk'],
      )!,
      decision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decision'],
      )!,
      resultSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_summary'],
      )!,
      isError: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_error'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
    );
  }

  @override
  $AuditRecordsTable createAlias(String alias) {
    return $AuditRecordsTable(attachedDatabase, alias);
  }
}

class AuditRecord extends DataClass implements Insertable<AuditRecord> {
  final int id;
  final String conversationId;
  final String messageId;
  final String toolCallId;
  final String toolName;
  final String arguments;
  final String risk;
  final String decision;
  final String resultSummary;
  final bool isError;
  final DateTime startedAt;
  final DateTime? finishedAt;
  const AuditRecord({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.toolCallId,
    required this.toolName,
    required this.arguments,
    required this.risk,
    required this.decision,
    required this.resultSummary,
    required this.isError,
    required this.startedAt,
    this.finishedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['message_id'] = Variable<String>(messageId);
    map['tool_call_id'] = Variable<String>(toolCallId);
    map['tool_name'] = Variable<String>(toolName);
    map['arguments'] = Variable<String>(arguments);
    map['risk'] = Variable<String>(risk);
    map['decision'] = Variable<String>(decision);
    map['result_summary'] = Variable<String>(resultSummary);
    map['is_error'] = Variable<bool>(isError);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    return map;
  }

  AuditRecordsCompanion toCompanion(bool nullToAbsent) {
    return AuditRecordsCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      messageId: Value(messageId),
      toolCallId: Value(toolCallId),
      toolName: Value(toolName),
      arguments: Value(arguments),
      risk: Value(risk),
      decision: Value(decision),
      resultSummary: Value(resultSummary),
      isError: Value(isError),
      startedAt: Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
    );
  }

  factory AuditRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditRecord(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      toolCallId: serializer.fromJson<String>(json['toolCallId']),
      toolName: serializer.fromJson<String>(json['toolName']),
      arguments: serializer.fromJson<String>(json['arguments']),
      risk: serializer.fromJson<String>(json['risk']),
      decision: serializer.fromJson<String>(json['decision']),
      resultSummary: serializer.fromJson<String>(json['resultSummary']),
      isError: serializer.fromJson<bool>(json['isError']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'messageId': serializer.toJson<String>(messageId),
      'toolCallId': serializer.toJson<String>(toolCallId),
      'toolName': serializer.toJson<String>(toolName),
      'arguments': serializer.toJson<String>(arguments),
      'risk': serializer.toJson<String>(risk),
      'decision': serializer.toJson<String>(decision),
      'resultSummary': serializer.toJson<String>(resultSummary),
      'isError': serializer.toJson<bool>(isError),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
    };
  }

  AuditRecord copyWith({
    int? id,
    String? conversationId,
    String? messageId,
    String? toolCallId,
    String? toolName,
    String? arguments,
    String? risk,
    String? decision,
    String? resultSummary,
    bool? isError,
    DateTime? startedAt,
    Value<DateTime?> finishedAt = const Value.absent(),
  }) => AuditRecord(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    messageId: messageId ?? this.messageId,
    toolCallId: toolCallId ?? this.toolCallId,
    toolName: toolName ?? this.toolName,
    arguments: arguments ?? this.arguments,
    risk: risk ?? this.risk,
    decision: decision ?? this.decision,
    resultSummary: resultSummary ?? this.resultSummary,
    isError: isError ?? this.isError,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
  );
  AuditRecord copyWithCompanion(AuditRecordsCompanion data) {
    return AuditRecord(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      toolCallId: data.toolCallId.present
          ? data.toolCallId.value
          : this.toolCallId,
      toolName: data.toolName.present ? data.toolName.value : this.toolName,
      arguments: data.arguments.present ? data.arguments.value : this.arguments,
      risk: data.risk.present ? data.risk.value : this.risk,
      decision: data.decision.present ? data.decision.value : this.decision,
      resultSummary: data.resultSummary.present
          ? data.resultSummary.value
          : this.resultSummary,
      isError: data.isError.present ? data.isError.value : this.isError,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditRecord(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolName: $toolName, ')
          ..write('arguments: $arguments, ')
          ..write('risk: $risk, ')
          ..write('decision: $decision, ')
          ..write('resultSummary: $resultSummary, ')
          ..write('isError: $isError, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    messageId,
    toolCallId,
    toolName,
    arguments,
    risk,
    decision,
    resultSummary,
    isError,
    startedAt,
    finishedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditRecord &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.messageId == this.messageId &&
          other.toolCallId == this.toolCallId &&
          other.toolName == this.toolName &&
          other.arguments == this.arguments &&
          other.risk == this.risk &&
          other.decision == this.decision &&
          other.resultSummary == this.resultSummary &&
          other.isError == this.isError &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt);
}

class AuditRecordsCompanion extends UpdateCompanion<AuditRecord> {
  final Value<int> id;
  final Value<String> conversationId;
  final Value<String> messageId;
  final Value<String> toolCallId;
  final Value<String> toolName;
  final Value<String> arguments;
  final Value<String> risk;
  final Value<String> decision;
  final Value<String> resultSummary;
  final Value<bool> isError;
  final Value<DateTime> startedAt;
  final Value<DateTime?> finishedAt;
  const AuditRecordsCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.toolCallId = const Value.absent(),
    this.toolName = const Value.absent(),
    this.arguments = const Value.absent(),
    this.risk = const Value.absent(),
    this.decision = const Value.absent(),
    this.resultSummary = const Value.absent(),
    this.isError = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
  });
  AuditRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String conversationId,
    required String messageId,
    required String toolCallId,
    required String toolName,
    required String arguments,
    required String risk,
    required String decision,
    this.resultSummary = const Value.absent(),
    this.isError = const Value.absent(),
    required DateTime startedAt,
    this.finishedAt = const Value.absent(),
  }) : conversationId = Value(conversationId),
       messageId = Value(messageId),
       toolCallId = Value(toolCallId),
       toolName = Value(toolName),
       arguments = Value(arguments),
       risk = Value(risk),
       decision = Value(decision),
       startedAt = Value(startedAt);
  static Insertable<AuditRecord> custom({
    Expression<int>? id,
    Expression<String>? conversationId,
    Expression<String>? messageId,
    Expression<String>? toolCallId,
    Expression<String>? toolName,
    Expression<String>? arguments,
    Expression<String>? risk,
    Expression<String>? decision,
    Expression<String>? resultSummary,
    Expression<bool>? isError,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (messageId != null) 'message_id': messageId,
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (toolName != null) 'tool_name': toolName,
      if (arguments != null) 'arguments': arguments,
      if (risk != null) 'risk': risk,
      if (decision != null) 'decision': decision,
      if (resultSummary != null) 'result_summary': resultSummary,
      if (isError != null) 'is_error': isError,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
    });
  }

  AuditRecordsCompanion copyWith({
    Value<int>? id,
    Value<String>? conversationId,
    Value<String>? messageId,
    Value<String>? toolCallId,
    Value<String>? toolName,
    Value<String>? arguments,
    Value<String>? risk,
    Value<String>? decision,
    Value<String>? resultSummary,
    Value<bool>? isError,
    Value<DateTime>? startedAt,
    Value<DateTime?>? finishedAt,
  }) {
    return AuditRecordsCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      arguments: arguments ?? this.arguments,
      risk: risk ?? this.risk,
      decision: decision ?? this.decision,
      resultSummary: resultSummary ?? this.resultSummary,
      isError: isError ?? this.isError,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (toolCallId.present) {
      map['tool_call_id'] = Variable<String>(toolCallId.value);
    }
    if (toolName.present) {
      map['tool_name'] = Variable<String>(toolName.value);
    }
    if (arguments.present) {
      map['arguments'] = Variable<String>(arguments.value);
    }
    if (risk.present) {
      map['risk'] = Variable<String>(risk.value);
    }
    if (decision.present) {
      map['decision'] = Variable<String>(decision.value);
    }
    if (resultSummary.present) {
      map['result_summary'] = Variable<String>(resultSummary.value);
    }
    if (isError.present) {
      map['is_error'] = Variable<bool>(isError.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditRecordsCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolName: $toolName, ')
          ..write('arguments: $arguments, ')
          ..write('risk: $risk, ')
          ..write('decision: $decision, ')
          ..write('resultSummary: $resultSummary, ')
          ..write('isError: $isError, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }
}

class $MemoriesTable extends Memories
    with TableInfo<$MemoriesTable, MemoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _textValueMeta = const VerificationMeta(
    'textValue',
  );
  @override
  late final GeneratedColumn<String> textValue = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMessageIdMeta = const VerificationMeta(
    'sourceMessageId',
  );
  @override
  late final GeneratedColumn<String> sourceMessageId = GeneratedColumn<String>(
    'source_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<String> revision = GeneratedColumn<String>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    textValue,
    kind,
    pinned,
    createdAt,
    updatedAt,
    sourceMessageId,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memories';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _textValueMeta,
        textValue.isAcceptableOrUnknown(data['text']!, _textValueMeta),
      );
    } else if (isInserting) {
      context.missing(_textValueMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('source_message_id')) {
      context.handle(
        _sourceMessageIdMeta,
        sourceMessageId.isAcceptableOrUnknown(
          data['source_message_id']!,
          _sourceMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MemoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      textValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      sourceMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_message_id'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $MemoriesTable createAlias(String alias) {
    return $MemoriesTable(attachedDatabase, alias);
  }
}

class MemoryRow extends DataClass implements Insertable<MemoryRow> {
  final String id;
  final String textValue;
  final String kind;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sourceMessageId;
  final String revision;
  const MemoryRow({
    required this.id,
    required this.textValue,
    required this.kind,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    this.sourceMessageId,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['text'] = Variable<String>(textValue);
    map['kind'] = Variable<String>(kind);
    map['pinned'] = Variable<bool>(pinned);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || sourceMessageId != null) {
      map['source_message_id'] = Variable<String>(sourceMessageId);
    }
    map['revision'] = Variable<String>(revision);
    return map;
  }

  MemoriesCompanion toCompanion(bool nullToAbsent) {
    return MemoriesCompanion(
      id: Value(id),
      textValue: Value(textValue),
      kind: Value(kind),
      pinned: Value(pinned),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      sourceMessageId: sourceMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMessageId),
      revision: Value(revision),
    );
  }

  factory MemoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoryRow(
      id: serializer.fromJson<String>(json['id']),
      textValue: serializer.fromJson<String>(json['textValue']),
      kind: serializer.fromJson<String>(json['kind']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      sourceMessageId: serializer.fromJson<String?>(json['sourceMessageId']),
      revision: serializer.fromJson<String>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'textValue': serializer.toJson<String>(textValue),
      'kind': serializer.toJson<String>(kind),
      'pinned': serializer.toJson<bool>(pinned),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'sourceMessageId': serializer.toJson<String?>(sourceMessageId),
      'revision': serializer.toJson<String>(revision),
    };
  }

  MemoryRow copyWith({
    String? id,
    String? textValue,
    String? kind,
    bool? pinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> sourceMessageId = const Value.absent(),
    String? revision,
  }) => MemoryRow(
    id: id ?? this.id,
    textValue: textValue ?? this.textValue,
    kind: kind ?? this.kind,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sourceMessageId: sourceMessageId.present
        ? sourceMessageId.value
        : this.sourceMessageId,
    revision: revision ?? this.revision,
  );
  MemoryRow copyWithCompanion(MemoriesCompanion data) {
    return MemoryRow(
      id: data.id.present ? data.id.value : this.id,
      textValue: data.textValue.present ? data.textValue.value : this.textValue,
      kind: data.kind.present ? data.kind.value : this.kind,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sourceMessageId: data.sourceMessageId.present
          ? data.sourceMessageId.value
          : this.sourceMessageId,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoryRow(')
          ..write('id: $id, ')
          ..write('textValue: $textValue, ')
          ..write('kind: $kind, ')
          ..write('pinned: $pinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sourceMessageId: $sourceMessageId, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    textValue,
    kind,
    pinned,
    createdAt,
    updatedAt,
    sourceMessageId,
    revision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryRow &&
          other.id == this.id &&
          other.textValue == this.textValue &&
          other.kind == this.kind &&
          other.pinned == this.pinned &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.sourceMessageId == this.sourceMessageId &&
          other.revision == this.revision);
}

class MemoriesCompanion extends UpdateCompanion<MemoryRow> {
  final Value<String> id;
  final Value<String> textValue;
  final Value<String> kind;
  final Value<bool> pinned;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> sourceMessageId;
  final Value<String> revision;
  final Value<int> rowid;
  const MemoriesCompanion({
    this.id = const Value.absent(),
    this.textValue = const Value.absent(),
    this.kind = const Value.absent(),
    this.pinned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sourceMessageId = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoriesCompanion.insert({
    required String id,
    required String textValue,
    required String kind,
    this.pinned = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.sourceMessageId = const Value.absent(),
    required String revision,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       textValue = Value(textValue),
       kind = Value(kind),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       revision = Value(revision);
  static Insertable<MemoryRow> custom({
    Expression<String>? id,
    Expression<String>? textValue,
    Expression<String>? kind,
    Expression<bool>? pinned,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? sourceMessageId,
    Expression<String>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (textValue != null) 'text': textValue,
      if (kind != null) 'kind': kind,
      if (pinned != null) 'pinned': pinned,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sourceMessageId != null) 'source_message_id': sourceMessageId,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? textValue,
    Value<String>? kind,
    Value<bool>? pinned,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? sourceMessageId,
    Value<String>? revision,
    Value<int>? rowid,
  }) {
    return MemoriesCompanion(
      id: id ?? this.id,
      textValue: textValue ?? this.textValue,
      kind: kind ?? this.kind,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (textValue.present) {
      map['text'] = Variable<String>(textValue.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (sourceMessageId.present) {
      map['source_message_id'] = Variable<String>(sourceMessageId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<String>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoriesCompanion(')
          ..write('id: $id, ')
          ..write('textValue: $textValue, ')
          ..write('kind: $kind, ')
          ..write('pinned: $pinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sourceMessageId: $sourceMessageId, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConversationRecordsTable conversationRecords =
      $ConversationRecordsTable(this);
  late final $MessageRecordsTable messageRecords = $MessageRecordsTable(this);
  late final $ProviderRecordsTable providerRecords = $ProviderRecordsTable(
    this,
  );
  late final $SettingRecordsTable settingRecords = $SettingRecordsTable(this);
  late final $AuditRecordsTable auditRecords = $AuditRecordsTable(this);
  late final $MemoriesTable memories = $MemoriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    conversationRecords,
    messageRecords,
    providerRecords,
    settingRecords,
    auditRecords,
    memories,
  ];
}

typedef $$ConversationRecordsTableCreateCompanionBuilder =
    ConversationRecordsCompanion Function({
      required String id,
      required String data,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ConversationRecordsTableUpdateCompanionBuilder =
    ConversationRecordsCompanion Function({
      Value<String> id,
      Value<String> data,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ConversationRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ConversationRecordsTable,
          ConversationRecord
        > {
  $$ConversationRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$MessageRecordsTable, List<MessageRecord>>
  _messageRecordsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.messageRecords,
    aliasName: 'conversation_records__id__message_records__conversation_id',
  );

  $$MessageRecordsTableProcessedTableManager get messageRecordsRefs {
    final manager = $$MessageRecordsTableTableManager(
      $_db,
      $_db.messageRecords,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_messageRecordsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ConversationRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationRecordsTable> {
  $$ConversationRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> messageRecordsRefs(
    Expression<bool> Function($$MessageRecordsTableFilterComposer f) f,
  ) {
    final $$MessageRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messageRecords,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageRecordsTableFilterComposer(
            $db: $db,
            $table: $db.messageRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationRecordsTable> {
  $$ConversationRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationRecordsTable> {
  $$ConversationRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> messageRecordsRefs<T extends Object>(
    Expression<T> Function($$MessageRecordsTableAnnotationComposer a) f,
  ) {
    final $$MessageRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messageRecords,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.messageRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationRecordsTable,
          ConversationRecord,
          $$ConversationRecordsTableFilterComposer,
          $$ConversationRecordsTableOrderingComposer,
          $$ConversationRecordsTableAnnotationComposer,
          $$ConversationRecordsTableCreateCompanionBuilder,
          $$ConversationRecordsTableUpdateCompanionBuilder,
          (ConversationRecord, $$ConversationRecordsTableReferences),
          ConversationRecord,
          PrefetchHooks Function({bool messageRecordsRefs})
        > {
  $$ConversationRecordsTableTableManager(
    _$AppDatabase db,
    $ConversationRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ConversationRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationRecordsCompanion(
                id: id,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String data,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ConversationRecordsCompanion.insert(
                id: id,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ConversationRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messageRecordsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (messageRecordsRefs) db.messageRecords,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messageRecordsRefs)
                    await $_getPrefetchedData<
                      ConversationRecord,
                      $ConversationRecordsTable,
                      MessageRecord
                    >(
                      currentTable: table,
                      referencedTable: $$ConversationRecordsTableReferences
                          ._messageRecordsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ConversationRecordsTableReferences(
                            db,
                            table,
                            p0,
                          ).messageRecordsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.conversationId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ConversationRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationRecordsTable,
      ConversationRecord,
      $$ConversationRecordsTableFilterComposer,
      $$ConversationRecordsTableOrderingComposer,
      $$ConversationRecordsTableAnnotationComposer,
      $$ConversationRecordsTableCreateCompanionBuilder,
      $$ConversationRecordsTableUpdateCompanionBuilder,
      (ConversationRecord, $$ConversationRecordsTableReferences),
      ConversationRecord,
      PrefetchHooks Function({bool messageRecordsRefs})
    >;
typedef $$MessageRecordsTableCreateCompanionBuilder =
    MessageRecordsCompanion Function({
      required String id,
      required String conversationId,
      Value<String?> parentId,
      required String status,
      required DateTime createdAt,
      required String data,
      Value<int> rowid,
    });
typedef $$MessageRecordsTableUpdateCompanionBuilder =
    MessageRecordsCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String?> parentId,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<String> data,
      Value<int> rowid,
    });

final class $$MessageRecordsTableReferences
    extends BaseReferences<_$AppDatabase, $MessageRecordsTable, MessageRecord> {
  $$MessageRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ConversationRecordsTable _conversationIdTable(_$AppDatabase db) =>
      db.conversationRecords.createAlias(
        'message_records__conversation_id__conversation_records__id',
      );

  $$ConversationRecordsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$ConversationRecordsTableTableManager(
      $_db,
      $_db.conversationRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessageRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $MessageRecordsTable> {
  $$MessageRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  $$ConversationRecordsTableFilterComposer get conversationId {
    final $$ConversationRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversationRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationRecordsTableFilterComposer(
            $db: $db,
            $table: $db.conversationRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $MessageRecordsTable> {
  $$MessageRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationRecordsTableOrderingComposer get conversationId {
    final $$ConversationRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.conversationId,
          referencedTable: $db.conversationRecords,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ConversationRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.conversationRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$MessageRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessageRecordsTable> {
  $$MessageRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  $$ConversationRecordsTableAnnotationComposer get conversationId {
    final $$ConversationRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.conversationId,
          referencedTable: $db.conversationRecords,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ConversationRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.conversationRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$MessageRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessageRecordsTable,
          MessageRecord,
          $$MessageRecordsTableFilterComposer,
          $$MessageRecordsTableOrderingComposer,
          $$MessageRecordsTableAnnotationComposer,
          $$MessageRecordsTableCreateCompanionBuilder,
          $$MessageRecordsTableUpdateCompanionBuilder,
          (MessageRecord, $$MessageRecordsTableReferences),
          MessageRecord,
          PrefetchHooks Function({bool conversationId})
        > {
  $$MessageRecordsTableTableManager(
    _$AppDatabase db,
    $MessageRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageRecordsCompanion(
                id: id,
                conversationId: conversationId,
                parentId: parentId,
                status: status,
                createdAt: createdAt,
                data: data,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                Value<String?> parentId = const Value.absent(),
                required String status,
                required DateTime createdAt,
                required String data,
                Value<int> rowid = const Value.absent(),
              }) => MessageRecordsCompanion.insert(
                id: id,
                conversationId: conversationId,
                parentId: parentId,
                status: status,
                createdAt: createdAt,
                data: data,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessageRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.conversationId,
                                referencedTable: $$MessageRecordsTableReferences
                                    ._conversationIdTable(db),
                                referencedColumn:
                                    $$MessageRecordsTableReferences
                                        ._conversationIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessageRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessageRecordsTable,
      MessageRecord,
      $$MessageRecordsTableFilterComposer,
      $$MessageRecordsTableOrderingComposer,
      $$MessageRecordsTableAnnotationComposer,
      $$MessageRecordsTableCreateCompanionBuilder,
      $$MessageRecordsTableUpdateCompanionBuilder,
      (MessageRecord, $$MessageRecordsTableReferences),
      MessageRecord,
      PrefetchHooks Function({bool conversationId})
    >;
typedef $$ProviderRecordsTableCreateCompanionBuilder =
    ProviderRecordsCompanion Function({
      required String id,
      required String data,
      Value<int> rowid,
    });
typedef $$ProviderRecordsTableUpdateCompanionBuilder =
    ProviderRecordsCompanion Function({
      Value<String> id,
      Value<String> data,
      Value<int> rowid,
    });

class $$ProviderRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ProviderRecordsTable> {
  $$ProviderRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProviderRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProviderRecordsTable> {
  $$ProviderRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProviderRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProviderRecordsTable> {
  $$ProviderRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $$ProviderRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProviderRecordsTable,
          ProviderRecord,
          $$ProviderRecordsTableFilterComposer,
          $$ProviderRecordsTableOrderingComposer,
          $$ProviderRecordsTableAnnotationComposer,
          $$ProviderRecordsTableCreateCompanionBuilder,
          $$ProviderRecordsTableUpdateCompanionBuilder,
          (
            ProviderRecord,
            BaseReferences<
              _$AppDatabase,
              $ProviderRecordsTable,
              ProviderRecord
            >,
          ),
          ProviderRecord,
          PrefetchHooks Function()
        > {
  $$ProviderRecordsTableTableManager(
    _$AppDatabase db,
    $ProviderRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProviderRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProviderRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProviderRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProviderRecordsCompanion(id: id, data: data, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String data,
                Value<int> rowid = const Value.absent(),
              }) => ProviderRecordsCompanion.insert(
                id: id,
                data: data,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProviderRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProviderRecordsTable,
      ProviderRecord,
      $$ProviderRecordsTableFilterComposer,
      $$ProviderRecordsTableOrderingComposer,
      $$ProviderRecordsTableAnnotationComposer,
      $$ProviderRecordsTableCreateCompanionBuilder,
      $$ProviderRecordsTableUpdateCompanionBuilder,
      (
        ProviderRecord,
        BaseReferences<_$AppDatabase, $ProviderRecordsTable, ProviderRecord>,
      ),
      ProviderRecord,
      PrefetchHooks Function()
    >;
typedef $$SettingRecordsTableCreateCompanionBuilder =
    SettingRecordsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingRecordsTableUpdateCompanionBuilder =
    SettingRecordsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingRecordsTable> {
  $$SettingRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingRecordsTable> {
  $$SettingRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingRecordsTable> {
  $$SettingRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingRecordsTable,
          SettingRecord,
          $$SettingRecordsTableFilterComposer,
          $$SettingRecordsTableOrderingComposer,
          $$SettingRecordsTableAnnotationComposer,
          $$SettingRecordsTableCreateCompanionBuilder,
          $$SettingRecordsTableUpdateCompanionBuilder,
          (
            SettingRecord,
            BaseReferences<_$AppDatabase, $SettingRecordsTable, SettingRecord>,
          ),
          SettingRecord,
          PrefetchHooks Function()
        > {
  $$SettingRecordsTableTableManager(
    _$AppDatabase db,
    $SettingRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  SettingRecordsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingRecordsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingRecordsTable,
      SettingRecord,
      $$SettingRecordsTableFilterComposer,
      $$SettingRecordsTableOrderingComposer,
      $$SettingRecordsTableAnnotationComposer,
      $$SettingRecordsTableCreateCompanionBuilder,
      $$SettingRecordsTableUpdateCompanionBuilder,
      (
        SettingRecord,
        BaseReferences<_$AppDatabase, $SettingRecordsTable, SettingRecord>,
      ),
      SettingRecord,
      PrefetchHooks Function()
    >;
typedef $$AuditRecordsTableCreateCompanionBuilder =
    AuditRecordsCompanion Function({
      Value<int> id,
      required String conversationId,
      required String messageId,
      required String toolCallId,
      required String toolName,
      required String arguments,
      required String risk,
      required String decision,
      Value<String> resultSummary,
      Value<bool> isError,
      required DateTime startedAt,
      Value<DateTime?> finishedAt,
    });
typedef $$AuditRecordsTableUpdateCompanionBuilder =
    AuditRecordsCompanion Function({
      Value<int> id,
      Value<String> conversationId,
      Value<String> messageId,
      Value<String> toolCallId,
      Value<String> toolName,
      Value<String> arguments,
      Value<String> risk,
      Value<String> decision,
      Value<String> resultSummary,
      Value<bool> isError,
      Value<DateTime> startedAt,
      Value<DateTime?> finishedAt,
    });

class $$AuditRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $AuditRecordsTable> {
  $$AuditRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolCallId => $composableBuilder(
    column: $table.toolCallId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolName => $composableBuilder(
    column: $table.toolName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get arguments => $composableBuilder(
    column: $table.arguments,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get risk => $composableBuilder(
    column: $table.risk,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultSummary => $composableBuilder(
    column: $table.resultSummary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isError => $composableBuilder(
    column: $table.isError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $AuditRecordsTable> {
  $$AuditRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolCallId => $composableBuilder(
    column: $table.toolCallId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolName => $composableBuilder(
    column: $table.toolName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get arguments => $composableBuilder(
    column: $table.arguments,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get risk => $composableBuilder(
    column: $table.risk,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultSummary => $composableBuilder(
    column: $table.resultSummary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isError => $composableBuilder(
    column: $table.isError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuditRecordsTable> {
  $$AuditRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get toolCallId => $composableBuilder(
    column: $table.toolCallId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toolName =>
      $composableBuilder(column: $table.toolName, builder: (column) => column);

  GeneratedColumn<String> get arguments =>
      $composableBuilder(column: $table.arguments, builder: (column) => column);

  GeneratedColumn<String> get risk =>
      $composableBuilder(column: $table.risk, builder: (column) => column);

  GeneratedColumn<String> get decision =>
      $composableBuilder(column: $table.decision, builder: (column) => column);

  GeneratedColumn<String> get resultSummary => $composableBuilder(
    column: $table.resultSummary,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isError =>
      $composableBuilder(column: $table.isError, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );
}

class $$AuditRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AuditRecordsTable,
          AuditRecord,
          $$AuditRecordsTableFilterComposer,
          $$AuditRecordsTableOrderingComposer,
          $$AuditRecordsTableAnnotationComposer,
          $$AuditRecordsTableCreateCompanionBuilder,
          $$AuditRecordsTableUpdateCompanionBuilder,
          (
            AuditRecord,
            BaseReferences<_$AppDatabase, $AuditRecordsTable, AuditRecord>,
          ),
          AuditRecord,
          PrefetchHooks Function()
        > {
  $$AuditRecordsTableTableManager(_$AppDatabase db, $AuditRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> toolCallId = const Value.absent(),
                Value<String> toolName = const Value.absent(),
                Value<String> arguments = const Value.absent(),
                Value<String> risk = const Value.absent(),
                Value<String> decision = const Value.absent(),
                Value<String> resultSummary = const Value.absent(),
                Value<bool> isError = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
              }) => AuditRecordsCompanion(
                id: id,
                conversationId: conversationId,
                messageId: messageId,
                toolCallId: toolCallId,
                toolName: toolName,
                arguments: arguments,
                risk: risk,
                decision: decision,
                resultSummary: resultSummary,
                isError: isError,
                startedAt: startedAt,
                finishedAt: finishedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String conversationId,
                required String messageId,
                required String toolCallId,
                required String toolName,
                required String arguments,
                required String risk,
                required String decision,
                Value<String> resultSummary = const Value.absent(),
                Value<bool> isError = const Value.absent(),
                required DateTime startedAt,
                Value<DateTime?> finishedAt = const Value.absent(),
              }) => AuditRecordsCompanion.insert(
                id: id,
                conversationId: conversationId,
                messageId: messageId,
                toolCallId: toolCallId,
                toolName: toolName,
                arguments: arguments,
                risk: risk,
                decision: decision,
                resultSummary: resultSummary,
                isError: isError,
                startedAt: startedAt,
                finishedAt: finishedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AuditRecordsTable,
      AuditRecord,
      $$AuditRecordsTableFilterComposer,
      $$AuditRecordsTableOrderingComposer,
      $$AuditRecordsTableAnnotationComposer,
      $$AuditRecordsTableCreateCompanionBuilder,
      $$AuditRecordsTableUpdateCompanionBuilder,
      (
        AuditRecord,
        BaseReferences<_$AppDatabase, $AuditRecordsTable, AuditRecord>,
      ),
      AuditRecord,
      PrefetchHooks Function()
    >;
typedef $$MemoriesTableCreateCompanionBuilder =
    MemoriesCompanion Function({
      required String id,
      required String textValue,
      required String kind,
      Value<bool> pinned,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> sourceMessageId,
      required String revision,
      Value<int> rowid,
    });
typedef $$MemoriesTableUpdateCompanionBuilder =
    MemoriesCompanion Function({
      Value<String> id,
      Value<String> textValue,
      Value<String> kind,
      Value<bool> pinned,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> sourceMessageId,
      Value<String> revision,
      Value<int> rowid,
    });

class $$MemoriesTableFilterComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textValue => $composableBuilder(
    column: $table.textValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textValue => $composableBuilder(
    column: $table.textValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get textValue =>
      $composableBuilder(column: $table.textValue, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$MemoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemoriesTable,
          MemoryRow,
          $$MemoriesTableFilterComposer,
          $$MemoriesTableOrderingComposer,
          $$MemoriesTableAnnotationComposer,
          $$MemoriesTableCreateCompanionBuilder,
          $$MemoriesTableUpdateCompanionBuilder,
          (MemoryRow, BaseReferences<_$AppDatabase, $MemoriesTable, MemoryRow>),
          MemoryRow,
          PrefetchHooks Function()
        > {
  $$MemoriesTableTableManager(_$AppDatabase db, $MemoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> textValue = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> sourceMessageId = const Value.absent(),
                Value<String> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoriesCompanion(
                id: id,
                textValue: textValue,
                kind: kind,
                pinned: pinned,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sourceMessageId: sourceMessageId,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String textValue,
                required String kind,
                Value<bool> pinned = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> sourceMessageId = const Value.absent(),
                required String revision,
                Value<int> rowid = const Value.absent(),
              }) => MemoriesCompanion.insert(
                id: id,
                textValue: textValue,
                kind: kind,
                pinned: pinned,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sourceMessageId: sourceMessageId,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemoriesTable,
      MemoryRow,
      $$MemoriesTableFilterComposer,
      $$MemoriesTableOrderingComposer,
      $$MemoriesTableAnnotationComposer,
      $$MemoriesTableCreateCompanionBuilder,
      $$MemoriesTableUpdateCompanionBuilder,
      (MemoryRow, BaseReferences<_$AppDatabase, $MemoriesTable, MemoryRow>),
      MemoryRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConversationRecordsTableTableManager get conversationRecords =>
      $$ConversationRecordsTableTableManager(_db, _db.conversationRecords);
  $$MessageRecordsTableTableManager get messageRecords =>
      $$MessageRecordsTableTableManager(_db, _db.messageRecords);
  $$ProviderRecordsTableTableManager get providerRecords =>
      $$ProviderRecordsTableTableManager(_db, _db.providerRecords);
  $$SettingRecordsTableTableManager get settingRecords =>
      $$SettingRecordsTableTableManager(_db, _db.settingRecords);
  $$AuditRecordsTableTableManager get auditRecords =>
      $$AuditRecordsTableTableManager(_db, _db.auditRecords);
  $$MemoriesTableTableManager get memories =>
      $$MemoriesTableTableManager(_db, _db.memories);
}
