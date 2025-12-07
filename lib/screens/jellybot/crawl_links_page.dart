import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';
import 'package:fladder/screens/settings/settings_scaffold.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class JellybotCrawlLinksPage extends ConsumerStatefulWidget {
  const JellybotCrawlLinksPage({super.key});

  @override
  ConsumerState<JellybotCrawlLinksPage> createState() => _JellybotCrawlLinksPageState();
}

class _JellybotCrawlLinksPageState extends ConsumerState<JellybotCrawlLinksPage> {
  List<CrawlLinkDto> _crawlLinks = [];
  bool _isLoading = false;
  int _currentPage = 0;
  int _totalPages = 0;
  static const int _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _loadCrawlLinks();
  }

  Future<void> _loadCrawlLinks({int page = 0}) async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiCrawlLinksGet(page: page, limit: _pageSize);
      if (response.isSuccessful && response.body != null) {
        setState(() {
          _crawlLinks = response.body!.items ?? [];
          _currentPage = response.body!.currentPage ?? 0;
          _totalPages = response.body!.totalPages ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading crawl links: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteCrawlLink(CrawlLinkDto link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.jellybotDeleteLink),
        content: Text(context.localized.jellybotDeleteLinkConfirm(link.name ?? 'Unknown')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.localized.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.localized.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiCrawlLinksDelete(id: link.mediaId);
      if (response.isSuccessful) {
        _loadCrawlLinks(page: _currentPage);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.localized.jellybotLinkDeleted)),
          );
        }
      }
    } catch (e) {
      debugPrint('Error deleting crawl link: $e');
    }
  }

  Future<void> _renameCrawlLink(CrawlLinkDto link) async {
    final controller = TextEditingController(text: link.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.jellybotRenameLink),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: context.localized.name,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.localized.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.localized.save),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName.isEmpty || newName == link.name) return;

    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiCrawlLinksCrawlLinkIdRenamePut(
        crawlLinkId: link.mediaId,
        body: RenameCrawlLinkRequest(newName: newName),
      );
      if (response.isSuccessful) {
        _loadCrawlLinks(page: _currentPage);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.localized.jellybotLinkRenamed)),
          );
        }
      }
    } catch (e) {
      debugPrint('Error renaming crawl link: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      label: context.localized.jellybotCrawlLinks,
      items: [
        if (_isLoading)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ))
        else if (_crawlLinks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(context.localized.jellybotNoCrawlLinks)),
          )
        else ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _crawlLinks.length,
            itemBuilder: (context, index) {
              final link = _crawlLinks[index];
              return _CrawlLinkTile(
                link: link,
                onDelete: () => _deleteCrawlLink(link),
                onRename: () => _renameCrawlLink(link),
              );
            },
          ),
          // Pagination
          if (_totalPages > 1)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _currentPage > 0 ? () => _loadCrawlLinks(page: _currentPage - 1) : null,
                  ),
                  Text('${_currentPage + 1} / $_totalPages'),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _currentPage < _totalPages - 1 ? () => _loadCrawlLinks(page: _currentPage + 1) : null,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _CrawlLinkTile extends StatelessWidget {
  final CrawlLinkDto link;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _CrawlLinkTile({
    required this.link,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = link.hasError ?? false;
    final downloaded = link.downloaded ?? false;

    return ListTile(
      leading: link.thumbnailUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                link.thumbnailUrl!,
                width: 50,
                height: 70,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 50),
              ),
            )
          : const Icon(Icons.movie, size: 50),
      title: Text(link.name ?? 'Unknown'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (link.provider?.displayName != null)
            Text(link.provider!.displayName!),
          Row(
            children: [
              if (link.season != null)
                Text('S${link.season}'),
              if (link.quality != null) ...[
                const SizedBox(width: 8),
                Chip(
                  label: Text(link.quality!, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                downloaded ? Icons.check_circle : (hasError ? Icons.error : Icons.pending),
                size: 16,
                color: downloaded
                    ? Colors.green
                    : (hasError ? Colors.red : Colors.orange),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton(
        itemBuilder: (context) => [
          PopupMenuItem(
            onTap: onRename,
            child: Row(
              children: [
                const Icon(Icons.edit),
                const SizedBox(width: 8),
                Text(context.localized.rename),
              ],
            ),
          ),
          PopupMenuItem(
            onTap: onDelete,
            child: Row(
              children: [
                Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Text(context.localized.delete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

