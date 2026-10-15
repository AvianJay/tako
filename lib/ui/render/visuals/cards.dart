import 'dart:convert';

import 'package:flutter/material.dart';

enum CardsLayout { list, grid, stats }

class CardItem {
  const CardItem({
    this.icon,
    this.title,
    this.subtitle,
    this.text,
    this.value,
    this.delta,
  });

  final String? icon;
  final String? title;
  final String? subtitle;
  final String? text;
  final String? value;
  final String? delta;
}

/// Model-authored cards: a JSON array of items, or an object with `items`
/// and a `layout`. Items that all carry a `value` become stat tiles.
class CardsSpec {
  const CardsSpec(this.layout, this.items);

  factory CardsSpec.parse(String source) {
    final decoded = jsonDecode(source);
    var layout = '';
    final Object? items;
    if (decoded is Map) {
      final map = decoded.cast<String, Object?>();
      layout = (_field(map, const ['layout', 'style']) ?? '').toLowerCase();
      items = map['items'] ?? map['cards'];
    } else {
      items = decoded;
    }
    if (items is! List || items.isEmpty || items.length > maxItems) {
      throw const FormatException('Cards are a list of 1–24 items');
    }
    final cards = [
      for (final item in items)
        if (item is Map)
          _card(item.cast<String, Object?>())
        else if (item is String && item.trim().isNotEmpty)
          CardItem(title: item.trim()),
    ];
    if (cards.isEmpty ||
        cards.any(
          (c) => c.title == null && c.text == null && c.value == null,
        )) {
      throw const FormatException('Every card needs a title, text or value');
    }
    return CardsSpec(
      cards.every((c) => c.value != null)
          ? CardsLayout.stats
          : layout == 'grid'
          ? CardsLayout.grid
          : CardsLayout.list,
      List.unmodifiable(cards),
    );
  }

  static const maxItems = 24;

  final CardsLayout layout;
  final List<CardItem> items;
}

CardItem _card(Map<String, Object?> map) => CardItem(
  icon: _field(map, const ['icon', 'emoji']),
  title: _field(map, const ['title', 'name', 'label', 'heading']),
  subtitle: _field(map, const [
    'subtitle',
    'subheading',
    'tag',
    'meta',
    'caption',
    'category',
  ]),
  text: _field(map, const [
    'text',
    'body',
    'description',
    'desc',
    'content',
    'detail',
  ]),
  value: _field(map, const ['value', 'stat', 'metric', 'number']),
  delta: _field(map, const ['delta', 'change', 'diff', 'trend']),
);

String? _field(Map<String, Object?> map, List<String> names) {
  for (final name in names) {
    final text = switch (map[name]) {
      final String text => text.trim(),
      final num number => '$number',
      _ => null,
    };
    if (text != null && text.isNotEmpty) {
      return text.length > 600 ? '${text.substring(0, 600)}…' : text;
    }
  }
  return null;
}

/// A card with its Markdown fields already rendered as inline spans.
class CardContent {
  const CardContent({
    this.icon,
    this.title,
    this.subtitle,
    this.text,
    this.value,
    this.delta,
  });

  final String? icon;
  final InlineSpan? title;
  final InlineSpan? subtitle;
  final InlineSpan? text;
  final String? value;
  final String? delta;
}

class CardsView extends StatelessWidget {
  const CardsView({required this.layout, required this.items, super.key});

  final CardsLayout layout;
  final List<CardContent> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: layout == CardsLayout.list
        ? _list(context)
        : LayoutBuilder(
            builder: (context, constraints) => _grid(
              context,
              constraints.maxWidth >= 520 ? 3 : (items.length == 1 ? 1 : 2),
            ),
          ),
  );

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0)
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.icon != null || item.title != null) ...[
                  CardIcon(icon: item.icon, title: item.title, size: 52),
                  const SizedBox(width: 14),
                ],
                Expanded(child: _texts(context, item)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _texts(BuildContext context, CardContent item) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.title case final title?)
          Text.rich(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        if (item.subtitle case final subtitle?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        if (item.text case final text?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text.rich(text, style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }

  Widget _grid(BuildContext context, int columns) {
    final rows = <Widget>[];
    for (var start = 0; start < items.length; start += columns) {
      if (start > 0) rows.add(const SizedBox(height: 10));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = start; i < start + columns; i++) ...[
                if (i > start) const SizedBox(width: 10),
                Expanded(
                  child: i < items.length
                      ? _tile(context, items[i])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _tile(BuildContext context, CardContent item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final stats = layout == CardsLayout.stats;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: stats
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (item.icon != null) ...[
                      CardIcon(icon: item.icon, size: 28),
                      const SizedBox(width: 8),
                    ],
                    if (item.title case final title?)
                      Expanded(
                        child: Text.rich(
                          title,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.value!,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.delta case final delta?) _Delta(delta),
                if (item.subtitle ?? item.text case final detail?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text.rich(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.icon != null || item.title != null) ...[
                  CardIcon(icon: item.icon, title: item.title, size: 40),
                  const SizedBox(height: 10),
                ],
                _texts(context, item),
              ],
            ),
    );
  }
}

/// A signed change with a direction arrow. Its colour stays neutral: whether
/// up is good depends on the measure, which a card does not say.
class _Delta extends StatelessWidget {
  const _Delta(this.delta);
  final String delta;

  @override
  Widget build(BuildContext context) {
    final trimmed = delta.trimLeft();
    final icon = RegExp(r'^[+▲↑]').hasMatch(trimmed)
        ? Icons.arrow_upward
        : RegExp(r'^[-−▼↓]').hasMatch(trimmed)
        ? Icons.arrow_downward
        : null;
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: style?.color),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(
              icon == null
                  ? delta
                  : trimmed.replaceFirst(RegExp(r'^[▲↑▼↓]'), ''),
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded tile with a Material icon, an emoji, or the title's first
/// character when the icon name is unknown.
class CardIcon extends StatelessWidget {
  const CardIcon({required this.size, this.icon, this.title, super.key});

  final double size;
  final String? icon;
  final InlineSpan? title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = icon?.trim() ?? '';
    final data = cardIconData(name);
    final emoji =
        data == null && name.isNotEmpty && name.runes.any((r) => r > 0x2000);
    final fallback = (title?.toPlainText().trim() ?? '').characters.firstOrNull;
    if (data == null && !emoji && fallback == null) {
      return SizedBox(width: size, height: size);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * .28),
      ),
      alignment: Alignment.center,
      child: data != null
          ? Icon(data, size: size * .5, color: scheme.onSurfaceVariant)
          : Text(
              emoji
                  ? name.characters.take(2).toString()
                  : fallback!.toUpperCase(),
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: size * (emoji ? .46 : .42),
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

/// Material icon names and a few plain-word aliases. Unknown names fall back
/// to the card's initial.
IconData? cardIconData(String name) =>
    _icons[name
        .toLowerCase()
        .replaceFirst(RegExp(r'^icons\.'), '')
        .replaceAll(RegExp(r'[\s-]+'), '_')
        .replaceFirst(RegExp(r'_(?:outlined|outline|rounded|sharp)$'), '')];

const _icons = <String, IconData>{
  'dashboard': Icons.dashboard_outlined,
  'grid': Icons.grid_view_outlined,
  'grid_view': Icons.grid_view_outlined,
  'apps': Icons.apps,
  'widgets': Icons.widgets_outlined,
  'view_agenda': Icons.view_agenda_outlined,
  'cards': Icons.view_agenda_outlined,
  'bar_chart': Icons.bar_chart,
  'chart': Icons.bar_chart,
  'show_chart': Icons.show_chart,
  'pie_chart': Icons.pie_chart_outline,
  'insights': Icons.insights,
  'analytics': Icons.analytics_outlined,
  'trending_up': Icons.trending_up,
  'trending_down': Icons.trending_down,
  'table': Icons.table_chart_outlined,
  'table_chart': Icons.table_chart_outlined,
  'account_tree': Icons.account_tree_outlined,
  'flowchart': Icons.account_tree_outlined,
  'schema': Icons.schema_outlined,
  'hub': Icons.hub_outlined,
  'timeline': Icons.timeline,
  'lightbulb': Icons.lightbulb_outline,
  'idea': Icons.lightbulb_outline,
  'tips_and_updates': Icons.tips_and_updates_outlined,
  'info': Icons.info_outline,
  'help': Icons.help_outline,
  'question': Icons.help_outline,
  'warning': Icons.warning_amber_rounded,
  'error': Icons.error_outline,
  'check': Icons.check_circle_outline,
  'check_circle': Icons.check_circle_outline,
  'done': Icons.done,
  'task_alt': Icons.task_alt,
  'checklist': Icons.checklist,
  'star': Icons.star_outline,
  'favorite': Icons.favorite_border,
  'heart': Icons.favorite_border,
  'thumb_up': Icons.thumb_up_outlined,
  'bolt': Icons.bolt,
  'speed': Icons.speed,
  'rocket': Icons.rocket_launch_outlined,
  'rocket_launch': Icons.rocket_launch_outlined,
  'auto_awesome': Icons.auto_awesome_outlined,
  'ai': Icons.auto_awesome_outlined,
  'smart_toy': Icons.smart_toy_outlined,
  'robot': Icons.smart_toy_outlined,
  'psychology': Icons.psychology_outlined,
  'settings': Icons.settings_outlined,
  'tune': Icons.tune,
  'build': Icons.build_outlined,
  'tools': Icons.build_outlined,
  'extension': Icons.extension_outlined,
  'code': Icons.code,
  'terminal': Icons.terminal,
  'bug_report': Icons.bug_report_outlined,
  'bug': Icons.bug_report_outlined,
  'api': Icons.api,
  'memory': Icons.memory,
  'storage': Icons.storage,
  'database': Icons.storage,
  'cloud': Icons.cloud_outlined,
  'devices': Icons.devices,
  'smartphone': Icons.smartphone,
  'phone': Icons.smartphone,
  'computer': Icons.computer,
  'laptop': Icons.laptop,
  'wifi': Icons.wifi,
  'battery': Icons.battery_full,
  'place': Icons.place_outlined,
  'location': Icons.place_outlined,
  'map': Icons.map_outlined,
  'explore': Icons.explore_outlined,
  'public': Icons.public,
  'language': Icons.language,
  'search': Icons.search,
  'link': Icons.link,
  'share': Icons.share_outlined,
  'lock': Icons.lock_outline,
  'security': Icons.security,
  'shield': Icons.shield_outlined,
  'key': Icons.key,
  'visibility': Icons.visibility_outlined,
  'person': Icons.person_outline,
  'user': Icons.person_outline,
  'people': Icons.people_outline,
  'groups': Icons.groups_outlined,
  'chat': Icons.chat_bubble_outline,
  'forum': Icons.forum_outlined,
  'mail': Icons.mail_outline,
  'email': Icons.mail_outline,
  'call': Icons.call_outlined,
  'notifications': Icons.notifications_none,
  'campaign': Icons.campaign_outlined,
  'calendar': Icons.calendar_today_outlined,
  'calendar_today': Icons.calendar_today_outlined,
  'event': Icons.event_outlined,
  'schedule': Icons.schedule,
  'time': Icons.schedule,
  'timer': Icons.timer_outlined,
  'history': Icons.history,
  'update': Icons.update,
  'home': Icons.home_outlined,
  'work': Icons.work_outline,
  'business': Icons.business,
  'school': Icons.school_outlined,
  'book': Icons.menu_book_outlined,
  'menu_book': Icons.menu_book_outlined,
  'article': Icons.article_outlined,
  'description': Icons.description_outlined,
  'document': Icons.description_outlined,
  'edit': Icons.edit_outlined,
  'folder': Icons.folder_outlined,
  'list': Icons.list,
  'inventory': Icons.inventory_2_outlined,
  'image': Icons.image_outlined,
  'photo': Icons.image_outlined,
  'photo_camera': Icons.photo_camera_outlined,
  'camera': Icons.photo_camera_outlined,
  'videocam': Icons.videocam_outlined,
  'video': Icons.videocam_outlined,
  'movie': Icons.movie_outlined,
  'music_note': Icons.music_note,
  'music': Icons.music_note,
  'headphones': Icons.headphones,
  'mic': Icons.mic_none,
  'palette': Icons.palette_outlined,
  'brush': Icons.brush_outlined,
  'shopping_bag': Icons.shopping_bag_outlined,
  'shopping_cart': Icons.shopping_cart_outlined,
  'cart': Icons.shopping_cart_outlined,
  'storefront': Icons.storefront_outlined,
  'store': Icons.storefront_outlined,
  'payments': Icons.payments_outlined,
  'attach_money': Icons.attach_money,
  'money': Icons.attach_money,
  'savings': Icons.savings_outlined,
  'credit_card': Icons.credit_card,
  'wallet': Icons.account_balance_wallet_outlined,
  'receipt': Icons.receipt_long_outlined,
  'sell': Icons.sell_outlined,
  'card_giftcard': Icons.card_giftcard,
  'gift': Icons.card_giftcard,
  'restaurant': Icons.restaurant,
  'food': Icons.restaurant,
  'coffee': Icons.coffee_outlined,
  'flight': Icons.flight,
  'travel': Icons.flight,
  'directions_car': Icons.directions_car_outlined,
  'car': Icons.directions_car_outlined,
  'train': Icons.train_outlined,
  'directions_bike': Icons.directions_bike,
  'hotel': Icons.hotel_outlined,
  'health_and_safety': Icons.health_and_safety_outlined,
  'health': Icons.health_and_safety_outlined,
  'medical_services': Icons.medical_services_outlined,
  'fitness_center': Icons.fitness_center,
  'fitness': Icons.fitness_center,
  'sports_soccer': Icons.sports_soccer,
  'mood': Icons.mood,
  'eco': Icons.eco_outlined,
  'park': Icons.park_outlined,
  'pets': Icons.pets,
  'wb_sunny': Icons.wb_sunny_outlined,
  'sunny': Icons.wb_sunny_outlined,
  'water_drop': Icons.water_drop_outlined,
  'thermostat': Icons.thermostat,
  'flag': Icons.flag_outlined,
  'track_changes': Icons.track_changes,
  'target': Icons.track_changes,
  'emoji_events': Icons.emoji_events_outlined,
  'trophy': Icons.emoji_events_outlined,
  'verified': Icons.verified_outlined,
  'layers': Icons.layers_outlined,
  'filter_alt': Icons.filter_alt_outlined,
  'sort': Icons.sort,
  'download': Icons.download,
  'upload': Icons.upload,
  'sync': Icons.sync,
  'compare_arrows': Icons.compare_arrows,
  'swap_horiz': Icons.swap_horiz,
  'arrow_forward': Icons.arrow_forward,
};
