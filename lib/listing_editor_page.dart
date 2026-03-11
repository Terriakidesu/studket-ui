import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api/listings_api.dart';
import 'api/tags_api.dart';

class ListingEditorPage extends StatefulWidget {
  const ListingEditorPage({
    super.key,
    this.listingType,
  });

  final String? listingType;

  bool get isLookingFor => listingType == 'looking_for';

  @override
  State<ListingEditorPage> createState() => _ListingEditorPageState();
}

class _ListingEditorPageState extends State<ListingEditorPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _budgetMinController = TextEditingController();
  final TextEditingController _budgetMaxController = TextEditingController();
  final TextEditingController _customTagController = TextEditingController();
  final List<File> _mediaFiles = <File>[];

  static const List<String> _conditions = <String>[
    'new',
    'like_new',
    'good',
    'fair',
    'poor',
  ];

  static const List<String> _saleListingTypes = <String>[
    'single_item',
    'stock_item',
  ];

  static const List<String> _fallbackTags = <String>[
    'food',
    'beverages',
    'school_supplies',
    'books',
    'academic_materials',
    'gadgets',
    'electronics',
    'clothing',
    'second_hand_items',
  ];

  String _selectedCondition = _conditions[2];
  String _selectedListingType = _saleListingTypes.first;
  final Set<String> _selectedTags = <String>{};
  List<String> _availableTags = _fallbackTags;
  bool _useBudgetRange = false;
  bool _isSubmitting = false;
  String? _submitError;

  bool get _isLookingForMode => widget.isLookingFor;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPopularTags());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    _customTagController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final num? amount = _parseOptionalNum(_priceController.text);
      final num? budgetMin = _useBudgetRange
          ? _parseOptionalNum(_budgetMinController.text)
          : amount;
      final num? budgetMax = _useBudgetRange
          ? _parseOptionalNum(_budgetMaxController.text)
          : null;
      if (_isLookingForMode &&
          budgetMin != null &&
          budgetMax != null &&
          budgetMin >= budgetMax) {
        throw const FormatException(
          'Budget maximum must be greater than budget minimum.',
        );
      }
      if (_isLookingForMode &&
          ((budgetMin != null && budgetMin < 0) ||
              (budgetMax != null && budgetMax < 0))) {
        throw const FormatException('Budget values cannot be negative.');
      }
      final Map<String, dynamic> createdListing = await ListingsApi.createListing(
        title: _titleController.text,
        description: _descriptionController.text,
        listingType: _isLookingForMode ? 'looking_for' : _selectedListingType,
        price: _isLookingForMode ? null : amount,
        budgetMin: _isLookingForMode ? budgetMin : null,
        budgetMax: _isLookingForMode ? budgetMax : null,
        condition: _isLookingForMode ? null : _selectedCondition,
        tags: _selectedTags.toList(growable: false),
      );

      if (!_isLookingForMode && _mediaFiles.isNotEmpty) {
        final int? listingId = ListingsApi.extractListingId(createdListing);
        if (listingId == null) {
          throw const HttpException(
            'Listing was created, but media upload could not start because the listing id was missing from the response.',
          );
        }
        await ListingsApi.uploadListingMedia(
          listingId: listingId,
          files: _mediaFiles,
        );
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on TimeoutException {
      _setSubmitError('Listing request timed out.');
    } on SocketException {
      _setSubmitError('Could not connect to the listings API.');
    } on HttpException catch (error) {
      _setSubmitError(error.message);
    } on FormatException {
      _setSubmitError(
        _isLookingForMode
            ? 'Budget values are invalid. Max must be greater than min, and negatives are not allowed.'
            : 'One or more numeric fields are invalid.',
      );
    } catch (_) {
      _setSubmitError('Failed to create post.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _setSubmitError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _submitError = message;
    });
  }

  num? _parseOptionalNum(String input) {
    final String normalized = input.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return num.parse(normalized);
  }

  Future<void> _pickMedia() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    if (result == null || !mounted) {
      return;
    }

    final List<File> selected = result.paths
        .whereType<String>()
        .map(File.new)
        .toList(growable: false);
    if (selected.isEmpty) {
      return;
    }

    setState(() {
      _mediaFiles
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _loadPopularTags() async {
    try {
      final List<String> tags = await TagsApi.fetchPopularTags();
      if (tags.isEmpty || !mounted) {
        return;
      }
      setState(() {
        _availableTags = tags.where((String tag) => tag != 'looking_for').toList(
          growable: false,
        );
      });
    } catch (_) {}
  }

  String _labelize(String value) {
    return value
        .split('_')
        .map(
          (String part) =>
              part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String _normalizeTag(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  void _toggleTag(String tag, bool selected) {
    setState(() {
      if (selected) {
        _selectedTags.add(tag);
      } else {
        _selectedTags.remove(tag);
      }
    });
  }

  void _addCustomTag() {
    final String normalized = _normalizeTag(_customTagController.text);
    if (normalized.isEmpty) {
      return;
    }
    setState(() {
      _selectedTags.add(normalized);
      _customTagController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags.remove(tag);
    });
  }

  InputDecoration _fieldDecoration(
    String label, {
    String? hintText,
    String? prefixText,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixText: prefixText,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF111827), width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isLookingFor = _isLookingForMode;
    final String title = isLookingFor
        ? 'Create Looking For Post'
        : 'Create Listing';
    final String subtitle = isLookingFor
        ? 'Describe what you need in a clear, compact post.'
        : 'Build a listing that feels clean, trustworthy, and easy to scan.';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _HeroPanel(
                title: title,
                subtitle: subtitle,
                accentLabel: isLookingFor ? 'Looking For' : 'Seller Listing',
                meta: isLookingFor
                    ? const <String>[
                        'No media upload',
                        'Single budget field',
                      ]
                    : const <String>[
                        'Photo upload supported',
                        'Condition required',
                      ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Details',
                subtitle: 'Lead with the essentials people will read first.',
                child: Column(
                  children: [
                    if (!isLookingFor) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _selectedListingType,
                        decoration: _fieldDecoration('Listing Type'),
                        items: _saleListingTypes.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(_labelize(value)),
                          );
                        }).toList(growable: false),
                        onChanged: (String? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _selectedListingType = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _titleController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _fieldDecoration(
                        'Title',
                        hintText: 'Used Scientific Calculator',
                      ),
                      validator: (String? value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Title is required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 5,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _fieldDecoration(
                        'Description',
                        hintText: isLookingFor
                            ? 'Describe what you need, preferred condition, and target budget range.'
                            : 'Describe the item, inclusions, meetup details, and any defects buyers should know about.',
                        alignLabelWithHint: true,
                      ),
                      validator: (String? value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Description is required.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Tags',
                subtitle: 'Use quick tags or add your own so the post lands in the right feed filters.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _customTagController,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _addCustomTag(),
                            decoration: _fieldDecoration(
                              'Custom Tag',
                              hintText: 'board_games, lab_goggles, dorm_decor',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: _addCustomTag,
                          icon: const Icon(Icons.add),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _availableTags
                          .map(
                            (String tag) => FilterChip(
                              label: Text(_labelize(tag)),
                              selected: _selectedTags.contains(tag),
                              onSelected: (bool selected) {
                                _toggleTag(tag, selected);
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                    if (_selectedTags.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Selected Tags',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF4B5563),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedTags
                            .map(
                              (String tag) => InputChip(
                                label: Text(tag),
                                onDeleted: () {
                                  _removeTag(tag);
                                },
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: isLookingFor ? 'Budget' : 'Pricing',
                subtitle: isLookingFor
                    ? 'Set the budget range you are willing to pay.'
                    : 'Keep the price direct and easy to compare.',
                child: isLookingFor
                    ? Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Use budget range'),
                            subtitle: Text(
                              _useBudgetRange
                                  ? 'Set a minimum and maximum budget.'
                                  : 'Use a single starting budget amount.',
                            ),
                            value: _useBudgetRange,
                            onChanged: (bool value) {
                              setState(() {
                                _useBudgetRange = value;
                                if (!value) {
                                  _budgetMaxController.clear();
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          if (_useBudgetRange)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _budgetMinController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: _fieldDecoration(
                                    'Budget Min',
                                    prefixText: 'PHP ',
                                  ),
                                  validator: (String? value) {
                                    final String normalized =
                                        (value ?? '').trim();
                                    final num? parsed = normalized.isEmpty
                                        ? null
                                        : num.tryParse(normalized);
                                    if (normalized.isNotEmpty &&
                                        parsed == null) {
                                      return 'Enter a valid amount.';
                                    }
                                    if (parsed != null && parsed < 0) {
                                      return 'Min cannot be negative.';
                                    }
                                    final num? maxValue = _parseOptionalNum(
                                      _budgetMaxController.text,
                                    );
                                    if (parsed != null &&
                                        maxValue != null &&
                                        parsed >= maxValue) {
                                      return 'Min must be less than max.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _budgetMaxController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: _fieldDecoration(
                                    'Budget Max',
                                    prefixText: 'PHP ',
                                  ),
                                  validator: (String? value) {
                                    final String normalized =
                                        (value ?? '').trim();
                                    final num? parsed = normalized.isEmpty
                                        ? null
                                        : num.tryParse(normalized);
                                    if (normalized.isNotEmpty &&
                                        parsed == null) {
                                      return 'Enter a valid amount.';
                                    }
                                    if (parsed != null && parsed < 0) {
                                      return 'Max cannot be negative.';
                                    }
                                    final num? minValue = _parseOptionalNum(
                                      _budgetMinController.text,
                                    );
                                    if (minValue != null &&
                                        parsed != null &&
                                        minValue >= parsed) {
                                      return 'Max must be greater than min.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (!_useBudgetRange)
                            TextFormField(
                              controller: _priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _fieldDecoration(
                                'Budget',
                                prefixText: 'PHP ',
                              ),
                              validator: (String? value) {
                                final String normalized = (value ?? '').trim();
                                final num? parsed = normalized.isEmpty
                                    ? null
                                    : num.tryParse(normalized);
                                if (normalized.isNotEmpty && parsed == null) {
                                  return 'Enter a valid amount.';
                                }
                                if (parsed != null && parsed < 0) {
                                  return 'Budget cannot be negative.';
                                }
                                return null;
                              },
                            ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _fieldDecoration(
                                'Price',
                                prefixText: 'PHP ',
                              ),
                              validator: (String? value) {
                                final String normalized = (value ?? '').trim();
                                if (normalized.isEmpty) {
                                  return 'Price is required.';
                                }
                                if (num.tryParse(normalized) == null) {
                                  return 'Enter a valid amount.';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          _InfoPill(
                            icon: Icons.payments_outlined,
                            label: 'Visible price',
                            onTap: () {
                              showDialog<void>(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text('Visible Price'),
                                    content: const Text(
                                      'This is the price buyers will see on the post.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
              ),
              if (!isLookingFor) ...[
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Item Setup',
                  subtitle: 'Small structure makes the form feel much cleaner.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCondition,
                        decoration: _fieldDecoration('Item Condition'),
                        items: _conditions.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(_labelize(value)),
                          );
                        }).toList(growable: false),
                        onChanged: (String? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _selectedCondition = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryTile(
                              title: 'Type',
                              value: _labelize(_selectedListingType),
                              icon: Icons.inventory_2_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SummaryTile(
                              title: 'Condition',
                              value: _labelize(_selectedCondition),
                              icon: Icons.workspace_premium_outlined,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Photos',
                  subtitle: 'Pick sharp images. Upload starts after the listing record is created.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F0FE),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.photo_library_outlined,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _mediaFiles.isEmpty
                                        ? 'No photos selected'
                                        : '${_mediaFiles.length} photo${_mediaFiles.length == 1 ? '' : 's'} selected',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Use bright images and keep the main item centered.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.tonalIcon(
                              onPressed: _isSubmitting ? null : _pickMedia,
                              icon: const Icon(Icons.add_photo_alternate_outlined),
                              label: Text(_mediaFiles.isEmpty ? 'Add' : 'Edit'),
                            ),
                          ],
                        ),
                      ),
                      if (_mediaFiles.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _mediaFiles.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 1,
                              ),
                          itemBuilder: (BuildContext context, int index) {
                            final File file = _mediaFiles[index];
                            return Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.file(
                                      file,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 6,
                                  top: 6,
                                  child: Material(
                                    color: Colors.black54,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _isSubmitting
                                          ? null
                                          : () {
                                              setState(() {
                                                _mediaFiles.removeAt(index);
                                              });
                                            },
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_submitError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _submitError!,
                    style: const TextStyle(color: Color(0xFF991B1B)),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isLookingFor
                              ? Icons.search_outlined
                              : Icons.sell_outlined,
                        ),
                  label: Text(
                    _isSubmitting
                        ? 'Posting...'
                        : isLookingFor
                        ? 'Publish Looking For Post'
                        : 'Publish Listing',
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

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.title,
    required this.subtitle,
    required this.accentLabel,
    required this.meta,
  });

  final String title;
  final String subtitle;
  final String accentLabel;
  final List<String> meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xFF111827),
            Color(0xFF1F2937),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A111827),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              accentLabel,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: meta
                .map(
                  (String item) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      item,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF111827),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF111827)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
