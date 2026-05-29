import 'package:flutter/material.dart';

import 'package:flutter_chat_demo/constants/constants.dart';

enum SearchFilter { all, messages, images, files }

class AdvancedSearchBar extends StatefulWidget {
  final Function(String query, SearchFilter filter) onSearch;
  final String hintText;

  const AdvancedSearchBar({
    super.key,
    required this.onSearch,
    this.hintText = 'Tìm kiếm...',
  });

  @override
  State<AdvancedSearchBar> createState() => _AdvancedSearchBarState();
}

class _AdvancedSearchBarState extends State<AdvancedSearchBar> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  SearchFilter _selectedFilter = SearchFilter.all;
  bool _showFilters = false;
  bool _isFocused = false;
  late AnimationController _filterCtrl;
  late Animation<double> _filterAnim;

  @override
  void initState() {
    super.initState();
    _filterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _filterAnim = CurvedAnimation(parent: _filterCtrl, curve: Curves.easeOut);
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  void _toggleFilters() {
    setState(() => _showFilters = !_showFilters);
    if (_showFilters) {
      _filterCtrl.forward();
    } else {
      _filterCtrl.reverse();
    }
  }

  void _clear() {
    _controller.clear();
    widget.onSearch('', _selectedFilter);
    setState(() {});
  }

  static const _filters = [
    (SearchFilter.all, Icons.apps_rounded, 'Tất cả'),
    (SearchFilter.messages, Icons.chat_bubble_outline_rounded, 'Tin nhắn'),
    (SearchFilter.images, Icons.image_outlined, 'Hình ảnh'),
    (SearchFilter.files, Icons.insert_drive_file_outlined, 'File'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasText = _controller.text.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: _isFocused
                ? ColorConstants.primaryColor.withValues(alpha: 0.3)
                : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
          ),
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                    color: ColorConstants.primaryColor.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ]
            : [],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isFocused
                          ? ColorConstants.primaryColor.withValues(alpha: 0.4)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _isFocused ? Icons.search_rounded : Icons.search_rounded,
                          key: ValueKey(_isFocused),
                          color: _isFocused ? ColorConstants.primaryColor : Colors.grey.shade400,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          style: TextStyle(
                              fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          onChanged: (v) {
                            setState(() {});
                            widget.onSearch(v, _selectedFilter);
                          },
                        ),
                      ),
                      if (hasText)
                        GestureDetector(
                          onTap: _clear,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey.shade400,
                              ),
                              child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleFilters,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _showFilters
                        ? ColorConstants.primaryColor
                        : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        color: _showFilters ? Colors.white : Colors.grey.shade500,
                        size: 20,
                      ),
                      if (_selectedFilter != SearchFilter.all && !_showFilters)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizeTransition(
            sizeFactor: _filterAnim,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: _filters.map((f) {
                  final (filter, icon, label) = f;
                  final isSelected = _selectedFilter == filter;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedFilter = filter);
                        widget.onSearch(_controller.text, filter);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? ColorConstants.primaryColor
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Icon(icon,
                                size: 18, color: isSelected ? Colors.white : Colors.grey.shade500),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                color: isSelected ? Colors.white : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
