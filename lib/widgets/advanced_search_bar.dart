// lib/widgets/advanced_search_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class AdvancedSearchBar extends StatefulWidget {
  final Function(String query, SearchFilter filter) onSearch;

  const AdvancedSearchBar({
    super.key,
    required this.onSearch,
  });

  @override
  State<AdvancedSearchBar> createState() => _AdvancedSearchBarState();
}

enum SearchFilter {
  all,
  messages,
  images,
  files,
}

class _AdvancedSearchBarState extends State<AdvancedSearchBar> {
  final _controller = TextEditingController();
  SearchFilter _selectedFilter = SearchFilter.all;
  bool _showFilters = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: ColorConstants.greyColor,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: ColorConstants.greyColor,
                            ),
                            onPressed: () {
                              _controller.clear();
                              widget.onSearch('', _selectedFilter);
                            },
                          ),
                        IconButton(
                          icon: Icon(
                            _showFilters ? Icons.filter_list : Icons.filter_list_outlined,
                            color: ColorConstants.primaryColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _showFilters = !_showFilters;
                            });
                          },
                        ),
                      ],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: ColorConstants.greyColor2,
                  ),
                  onChanged: (value) {
                    widget.onSearch(value, _selectedFilter);
                  },
                ),
              ),
            ],
          ),
          if (_showFilters) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(SearchFilter.all, 'All'),
                  _buildFilterChip(SearchFilter.messages, 'Messages'),
                  _buildFilterChip(SearchFilter.images, 'Images'),
                  _buildFilterChip(SearchFilter.files, 'Files'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(SearchFilter filter, String label) {
    final isSelected = _selectedFilter == filter;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = filter;
          });
          widget.onSearch(_controller.text, _selectedFilter);
        },
        selectedColor: ColorConstants.primaryColor,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : ColorConstants.primaryColor,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}