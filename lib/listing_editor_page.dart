import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api/listings_api.dart';

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
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _maxDailyLimitController = TextEditingController();
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

  String _selectedCondition = _conditions[2];
  String _selectedListingType = _saleListingTypes.first;
  bool _restockable = true;
  bool _isSubmitting = false;
  String? _submitError;

  bool get _isLookingForMode => widget.isLookingFor;

  bool get _isStockItem =>
      !_isLookingForMode && _selectedListingType == 'stock_item';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _tagsController.dispose();
    _quantityController.dispose();
    _maxDailyLimitController.dispose();
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
      final num? price = _parsePrice(_priceController.text);
      final List<String> tags = _parseTags(_tagsController.text);
      final int? quantityAvailable = _parseOptionalInt(_quantityController.text);
      final int? maxDailyLimit = _parseOptionalInt(
        _maxDailyLimitController.text,
      );

      final Map<String, dynamic> createdListing = await ListingsApi.createListing(
        title: _titleController.text,
        description: _descriptionController.text,
        listingType: _isLookingForMode ? 'looking_for' : _selectedListingType,
        price: price,
        condition: _isLookingForMode ? null : _selectedCondition,
        quantityAvailable: _isStockItem ? quantityAvailable : null,
        maxDailyLimit: _isStockItem ? maxDailyLimit : null,
        restockable: _isStockItem ? _restockable : null,
        tags: tags,
      );
      if (_mediaFiles.isNotEmpty) {
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
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = 'Listing request timed out.';
      });
    } on SocketException {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = 'Could not connect to the listings API.';
      });
    } on HttpException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = error.message;
      });
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = 'Price must be a valid number.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = 'Failed to create post.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  num? _parsePrice(String input) {
    final String normalized = input.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return num.parse(normalized);
  }

  List<String> _parseTags(String input) {
    return input
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  int? _parseOptionalInt(String input) {
    final String normalized = input.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return int.parse(normalized);
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

  @override
  Widget build(BuildContext context) {
    final bool isLookingFor = _isLookingForMode;
    final String title = isLookingFor
        ? 'Create Looking For Post'
        : 'Create Listing';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                isLookingFor
                    ? 'Describe what you want to buy so sellers can find you.'
                    : 'Post an item for sale on the marketplace feed.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 20),
              if (!isLookingFor) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedListingType,
                  decoration: const InputDecoration(
                    labelText: 'Listing Type',
                    border: OutlineInputBorder(),
                  ),
                  items: _saleListingTypes.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value.replaceAll('_', ' ')),
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
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
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
                minLines: 4,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (String? value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Description is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: isLookingFor ? 'Budget (optional)' : 'Price',
                  border: const OutlineInputBorder(),
                  prefixText: 'PHP ',
                ),
                validator: (String? value) {
                  final String normalized = (value ?? '').trim();
                  if (!isLookingFor && normalized.isEmpty) {
                    return 'Price is required.';
                  }
                  if (normalized.isNotEmpty && num.tryParse(normalized) == null) {
                    return 'Enter a valid amount.';
                  }
                  return null;
                },
              ),
              if (!isLookingFor) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCondition,
                  decoration: const InputDecoration(
                    labelText: 'Condition',
                    border: OutlineInputBorder(),
                  ),
                  items: _conditions.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value.replaceAll('_', ' ')),
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
              ],
              if (_isStockItem) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity Available',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) {
                    final String normalized = (value ?? '').trim();
                    if (normalized.isEmpty) {
                      return 'Quantity is required for stock items.';
                    }
                    if (int.tryParse(normalized) == null) {
                      return 'Enter a whole number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _maxDailyLimitController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max Daily Limit',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) {
                    final String normalized = (value ?? '').trim();
                    if (normalized.isNotEmpty &&
                        int.tryParse(normalized) == null) {
                      return 'Enter a whole number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _restockable,
                  onChanged: (bool value) {
                    setState(() {
                      _restockable = value;
                    });
                  },
                  title: const Text('Restockable'),
                  subtitle: const Text(
                    'Use this for repeatable stock instead of one-off items.',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _tagsController,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'books, electronics, dorm',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Listing Media',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _isSubmitting ? null : _pickMedia,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Add Photos'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _mediaFiles.isEmpty
                            ? 'No images selected yet.'
                            : '${_mediaFiles.length} image(s) selected. Upload starts after the listing is created.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[700],
                        ),
                      ),
                      if (_mediaFiles.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 96,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _mediaFiles.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (BuildContext context, int index) {
                              final File file = _mediaFiles[index];
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.file(
                                      file,
                                      width: 96,
                                      height: 96,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    right: 4,
                                    top: 4,
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
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    isLookingFor
                        ? 'This will be submitted as listing_type = looking_for.'
                        : 'This will be submitted under the listing model with seller ownership and optional inventory fields.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _submitError!,
                      style: TextStyle(color: Colors.red[900]),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
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
                      ? 'Post Looking For'
                      : 'Post Listing',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
