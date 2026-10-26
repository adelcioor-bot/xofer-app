import 'package:flutter/material.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/places/domain/place.dart';

class DestinationSearchBar extends StatelessWidget {
  const DestinationSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.originLabel,
    required this.originText,
    required this.originLoading,
    required this.destinationLabel,
    required this.hintText,
    required this.clearTooltip,
    required this.emptyText,
    required this.errorText,
    required this.isSearching,
    required this.showEmpty,
    required this.results,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSelected,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String originLabel;
  final String originText;
  final bool originLoading;
  final String destinationLabel;
  final String hintText;
  final String clearTooltip;
  final String emptyText;
  final String? errorText;
  final bool isSearching;
  final bool showEmpty;
  final List<Place> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<Place> onSelected;
  final VoidCallback onClear;

  bool get _showPanel {
    return isSearching || results.isNotEmpty || showEmpty || errorText != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppTheme.graphiteSurface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    const Icon(Icons.trip_origin, color: AppTheme.amber, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            originLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppTheme.amber,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          originLoading
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  ),
                                )
                              : Text(
                                  key: const Key('origin_address'),
                                  originText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  destinationLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextField(
            key: const Key('destination_search_field'),
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            onTapOutside: results.isNotEmpty
                ? (_) {}
                : (_) => focusNode.unfocus(),
            textInputAction: TextInputAction.search,
            cursorColor: AppTheme.amber,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              prefixIcon: const Icon(Icons.search, color: AppTheme.amber),
              suffixIcon: _suffix(),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
            ),
          ),
            ],
          ),
        ),
        if (_showPanel) ...[
          const SizedBox(height: 8),
          Material(
            key: const Key('destination_results'),
            color: AppTheme.graphiteSurface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: _panelBody(theme),
            ),
          ),
        ],
      ],
    );
  }

  Widget? _suffix() {
    if (isSearching) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (controller.text.isEmpty) return null;
    return IconButton(
      key: const Key('clear_destination_button'),
      tooltip: clearTooltip,
      onPressed: onClear,
      icon: const Icon(Icons.close, color: AppTheme.amber),
    );
  }

  Widget _panelBody(ThemeData theme) {
    if (errorText != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          key: const Key('destination_search_error'),
          errorText!,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    if (isSearching && results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (showEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          key: const Key('destination_search_empty'),
          emptyText,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: results.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: Colors.white.withValues(alpha: 0.08),
      ),
      itemBuilder: (context, index) {
        final place = results[index];
        final showDescription = place.description != place.label;
        return GestureDetector(
          key: Key('destination_result_$index'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => onSelected(place),
          onTap: () => onSelected(place),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place, color: AppTheme.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (showDescription) ...[
                        const SizedBox(height: 2),
                        Text(
                          place.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
