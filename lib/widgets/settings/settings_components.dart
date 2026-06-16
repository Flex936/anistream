import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';

class TabHeading extends StatelessWidget {
  final String title;
  const TabHeading({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppPalette.textMain,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String label;
  const SectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: AppPalette.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
    );
  }
}

class FolderInput extends StatefulWidget {
  final String path;
  final VoidCallback onTap;

  const FolderInput({super.key, required this.path, required this.onTap});

  @override
  State<FolderInput> createState() => _FolderInputState();
}

class _FolderInputState extends State<FolderInput> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.path.isEmpty;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppPalette.base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: 2,
              color: _hovered ? AppPalette.primary : AppPalette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_open_outlined,
                size: 18,
                color: _hovered ? AppPalette.primary : AppPalette.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEmpty ? 'Click to select a folder…' : widget.path,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isEmpty ? AppPalette.textMuted : AppPalette.textMain,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const ToggleSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          color: value ? AppPalette.primary : AppPalette.overlay,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? AppPalette.primary : AppPalette.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
