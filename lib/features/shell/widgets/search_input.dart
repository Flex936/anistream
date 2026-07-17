import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_palette.dart';
import '../../../data/anilist/anilist_query_service.dart';
import '../../../data/anilist/models/anime.dart';
import '../../../shared/utils/anime_status_style.dart';
import '../../../shared/widgets/app_network_image.dart';
import '../../../shared/widgets/frosted_container.dart';

class SearchInput extends StatefulWidget {
  final TextEditingController controller;
  final bool autoFocus;
  final bool uiPerformanceMode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<Anime>? onSelectAnime;
  final ValueChanged<String>? onSubmitted;

  const SearchInput({
    super.key,
    required this.controller,
    this.autoFocus = false,
    this.uiPerformanceMode = false,
    this.onChanged,
    this.onSelectAnime,
    this.onSubmitted,
  });

  @override
  State<SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<SearchInput> {
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  final AnilistQueryService _api = AnilistQueryService();
  Timer? _debounce;

  bool _isLoading = false;
  List<Anime> _instantMatches = [];

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        node.focusInDirection(TraversalDirection.up);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        node.focusInDirection(TraversalDirection.down);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        final offset = widget.controller.selection.baseOffset;
        if (offset == widget.controller.text.length || offset == -1) {
          node.focusInDirection(TraversalDirection.right);
          return KeyEventResult.handled;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        final offset = widget.controller.selection.baseOffset;
        if (offset <= 0) {
          node.focusInDirection(TraversalDirection.left);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && widget.controller.text.isNotEmpty) {
        _showOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 150), _hideOverlay);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _debounce?.cancel();
    _hideOverlay();
    _api.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    widget.onChanged?.call(value);

    if (value.trim().isEmpty) {
      setState(() {
        _instantMatches.clear();
        _isLoading = false;
      });
      _hideOverlay();
      return;
    }

    _showOverlay();
    setState(() => _isLoading = true);
    _overlayEntry?.markNeedsBuild();

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fetchMatches);
  }

  Future<void> _fetchMatches() async {
    try {
      final results = await _api.searchAnime(widget.controller.text);
      if (mounted) {
        setState(() {
          _instantMatches = results.take(3).toList();
          _isLoading = false;
        });
        _overlayEntry?.markNeedsBuild();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _overlayEntry?.markNeedsBuild();
      }
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final renderBox = context.findRenderObject() as RenderBox?;
        final width = renderBox?.size.width ?? 300.0;

        return Positioned(
          width: width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 48),
            child: _buildDropdown(),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildDropdown() {
    if (_isLoading && _instantMatches.isEmpty) {
      return _buildGlassContainer(
        height: 60,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppPalette.primary),
            ),
          ),
        ),
      );
    }

    if (_instantMatches.isEmpty) return const SizedBox.shrink();

    return _buildGlassContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _instantMatches.map((anime) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _hideOverlay();
                _focusNode.unfocus();
                widget.onSelectAnime?.call(anime);
              },
              hoverColor: AppPalette.white.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 32,
                        height: 48,
                        child: anime.coverImage?.display != null
                            ? AppNetworkImage(
                                url: anime.coverImage!.display!,
                                // ── cacheWidth added: this thumbnail
                                // renders at 32dp wide, yet was decoding
                                // a full-resolution poster. 100 gives ~3x headroom. ──
                                cacheWidth: 100,
                                uiPerformanceMode: widget.uiPerformanceMode,
                              )
                            : const ColoredBox(color: AppPalette.surface),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            anime.title.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppPalette.textMain,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: (anime.status ?? 'UNKNOWN').replaceAll(
                                    '_',
                                    ' ',
                                  ),
                                  style: TextStyle(
                                    color: anime.status?.statusColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                const TextSpan(
                                  text: '  •  ',
                                  style: TextStyle(
                                    color: AppPalette.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                TextSpan(
                                  text: '★ ${(anime.averageScore ?? 0) / 10}',
                                  style: const TextStyle(
                                    color: AppPalette.accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child, double? height}) {
    final content = Container(
      height: height,
      decoration: BoxDecoration(
        color: AppPalette.base.withValues(
          alpha: widget.uiPerformanceMode ? 0.98 : 0.85,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border.withValues(alpha: 0.5)),
        boxShadow: widget.uiPerformanceMode
            ? null
            : [
                BoxShadow(
                  color: AppPalette.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      child: child,
    );

    return FrostedContainer(
      uiPerformanceMode: widget.uiPerformanceMode,
      sigma: 16,
      borderRadius: BorderRadius.circular(16),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autoFocus,
        onChanged: _onTextChanged,
        onSubmitted: widget.onSubmitted,
        style: const TextStyle(color: AppPalette.textMain, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search for anime...',
          hintStyle: const TextStyle(color: AppPalette.textMuted, fontSize: 14),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              Icons.search_rounded,
              color: AppPalette.textMuted,
              size: 20,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, value, child) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(
                  Icons.cancel_rounded,
                  color: AppPalette.textMuted,
                  size: 18,
                ),
                onPressed: () {
                  widget.controller.clear();
                  _onTextChanged('');
                },
              );
            },
          ),
          filled: true,
          fillColor: AppPalette.white.withValues(alpha: 0.05),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 11,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: AppPalette.white.withValues(alpha: 0.1),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: AppPalette.white.withValues(alpha: 0.1),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}
