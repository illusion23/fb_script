import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/post_template.dart';
import '../services/poster_runner.dart';
import '../utils/compat_theme.dart';
import '../utils/text_direction_helper.dart';

/// Side-menu screen for creating, editing, duplicating, deleting, and
/// selecting the default post used by the Start button.
class PostsScreen extends StatelessWidget {
  const PostsScreen({super.key, required this.controller});

  final AppStateController controller;

  Future<void> _openEditor(
    BuildContext context, {
    PostTemplate? existing,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PostEditorSheet(
        controller: controller,
        existing: existing,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PostTemplate post,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post?'),
        content: Text('Delete "${post.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deletePost(post.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = controller.posts;
    final defaultId = controller.defaultPostId;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: posts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colorWithOpacity(scheme.primaryContainer, 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.post_add_rounded,
                        size: 56,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Saved Posts Yet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a post template with text and optional images, then select it as your Default Post.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      key: const Key('create_first_post_button'),
                      onPressed: () => _openEditor(context),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Create First Post'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final isDefault = post.id == defaultId;
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: appCardShape(
                    scheme,
                    borderColor: isDefault ? scheme.primary : null,
                    borderWidth: isDefault ? 2 : 1,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => controller.selectDefaultPost(post.id),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isDefault
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked,
                                color:
                                    isDefault ? scheme.primary : scheme.outline,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  post.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'DEFAULT',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (post.message.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorWithOpacity(
                                  surfaceContainerHighestCompat(scheme),
                                  0.45,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Directionality(
                                textDirection:
                                    detectTextDirection(post.message),
                                child: Text(
                                  post.message,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ),
                          ],
                          if (post.imagePaths.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 60,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: post.imagePaths.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (_, idx) {
                                  final path = post.imagePaths[idx];
                                  final file = File(path);
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: file.existsSync()
                                        ? Image.file(
                                            file,
                                            width: 60,
                                            height: 60,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 60,
                                            height: 60,
                                            color:
                                                surfaceContainerHighestCompat(
                                              scheme,
                                            ),
                                            child: const Icon(
                                                Icons.image_outlined),
                                          ),
                                  );
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (!isDefault)
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      controller.selectDefaultPost(post.id),
                                  icon: const Icon(Icons.check_circle_outline,
                                      size: 18),
                                  label: const Text('Use as Default'),
                                ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Duplicate',
                                icon: const Icon(Icons.copy_outlined, size: 20),
                                onPressed: () => controller.createPost(
                                  title: '${post.title} (Copy)',
                                  message: post.message,
                                  imagePaths: post.imagePaths,
                                  setAsDefault: false,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () =>
                                    _openEditor(context, existing: post),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon:
                                    const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => _confirmDelete(context, post),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_post_fab'),
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('New Post'),
      ),
    );
  }
}

class _PostEditorSheet extends StatefulWidget {
  const _PostEditorSheet({
    required this.controller,
    this.existing,
  });

  final AppStateController controller;
  final PostTemplate? existing;

  @override
  State<_PostEditorSheet> createState() => _PostEditorSheetState();
}

class _PostEditorSheetState extends State<_PostEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _messageController;
  late List<String> _imagePaths;
  bool _setAsDefault = true;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.existing?.title ?? '');
    _messageController =
        TextEditingController(text: widget.existing?.message ?? '');
    _imagePaths = List<String>.from(widget.existing?.imagePaths ?? const []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      if (files.isEmpty) return;
      setState(() {
        for (final f in files) {
          if (!_imagePaths.contains(f.path)) {
            _imagePaths.add(f.path);
          }
        }
      });
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick image: $err')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final msg = _messageController.text.trim();
    if (msg.isEmpty && _imagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a post message or attach an image.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (widget.existing == null) {
      await widget.controller.createPost(
        title: _titleController.text,
        message: msg,
        imagePaths: _imagePaths,
        setAsDefault: _setAsDefault,
      );
    } else {
      await widget.controller.updatePost(
        widget.existing!.copyWith(
          title: _titleController.text.trim().isEmpty
              ? 'Untitled Post'
              : _titleController.text.trim(),
          message: msg,
          imagePaths: _imagePaths,
        ),
      );
      if (_setAsDefault) {
        await widget.controller.selectDefaultPost(widget.existing!.id);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final dir = detectTextDirection(_messageController.text);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'Create Post' : 'Edit Post',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('post_title_field'),
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Post Title (for your reference)',
                ),
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? 'Enter a title'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('post_message_field'),
                controller: _messageController,
                textDirection: dir,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Post Message',
                  alignLabelWithHint: true,
                  helperText: '${_messageController.text.length} characters',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Attach Images'),
                  ),
                  const SizedBox(width: 10),
                  if (_imagePaths.isNotEmpty)
                    Text(
                      '${_imagePaths.length} attached',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              if (_imagePaths.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _imagePaths.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (_, idx) {
                      final path = _imagePaths[idx];
                      final file = File(path);
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: file.existsSync()
                                ? Image.file(
                                    file,
                                    width: 76,
                                    height: 76,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 76,
                                    height: 76,
                                    color: surfaceContainerHighestCompat(
                                      Theme.of(context).colorScheme,
                                    ),
                                    child: const Icon(Icons.image_outlined),
                                  ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _imagePaths.remove(path)),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
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
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Set as Default Post'),
                value: _setAsDefault,
                onChanged: (v) => setState(() => _setAsDefault = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('save_post_button'),
                onPressed: _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Post'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
