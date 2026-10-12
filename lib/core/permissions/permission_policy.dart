import 'dart:convert';

import '../util/json.dart';

enum ToolPermission { ask, allow, deny }

/// Explicit user preferences; chat-scoped approvals are intentionally absent.
class PermissionPolicy {
  const PermissionPolicy({
    this.fullPermissions = false,
    this.skipHighRiskConfirmations = false,
    this.overrides = const {},
    this.highRiskKeywords = defaultHighRiskKeywords,
  });

  static const settingsKey = 'permissions.policy';
  static const defaultHighRiskKeywords = [
    'send',
    'post',
    'pay',
    'buy',
    'order',
    'delete',
    'remove',
    'confirm',
    'install',
    'transfer',
    'download',
    'erase',
    'reset',
    'wipe',
    '發送',
    '发送',
    '送出',
    '傳送',
    '传送',
    '發布',
    '发布',
    '付款',
    '支付',
    '購買',
    '购买',
    '下單',
    '下单',
    '刪除',
    '删除',
    '移除',
    '確認',
    '确认',
    '安裝',
    '安装',
    '轉帳',
    '转账',
    '下載',
    '下载',
    '清除',
    '抹除',
    '重設',
    '重置',
  ];

  final bool fullPermissions;
  final bool skipHighRiskConfirmations;
  final Map<String, ToolPermission> overrides;
  final List<String> highRiskKeywords;

  PermissionPolicy copyWith({
    bool? fullPermissions,
    bool? skipHighRiskConfirmations,
    Map<String, ToolPermission>? overrides,
    List<String>? highRiskKeywords,
  }) => PermissionPolicy(
    fullPermissions: fullPermissions ?? this.fullPermissions,
    skipHighRiskConfirmations:
        skipHighRiskConfirmations ?? this.skipHighRiskConfirmations,
    overrides: overrides ?? this.overrides,
    highRiskKeywords: highRiskKeywords ?? this.highRiskKeywords,
  );

  JsonMap toJson() => {
    'fullPermissions': fullPermissions,
    'skipHighRiskConfirmations': skipHighRiskConfirmations,
    'overrides': {
      for (final entry in overrides.entries) entry.key: entry.value.name,
    },
    'highRiskKeywords': highRiskKeywords,
  };

  String encode() => jsonEncode(toJson());

  factory PermissionPolicy.decode(String? value) {
    final data = value == null ? null : tryDecodeObject(value);
    if (data == null) return const PermissionPolicy();
    return PermissionPolicy(
      fullPermissions: asBool(data['fullPermissions']) ?? false,
      skipHighRiskConfirmations:
          asBool(data['skipHighRiskConfirmations']) ?? false,
      overrides: {
        for (final entry in (asMap(data['overrides']) ?? {}).entries)
          for (final permission in ToolPermission.values)
            if (entry.value == permission.name) entry.key: permission,
      },
      highRiskKeywords: switch (asList(data['highRiskKeywords'])) {
        final values? => [
          for (final item in values)
            if (item is String && item.trim().isNotEmpty) item.trim(),
        ],
        null => defaultHighRiskKeywords,
      },
    );
  }
}
