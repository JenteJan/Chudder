import 'package:flutter/material.dart';

import 'package:fladder/models/syncing/transcode_download_model.dart';
import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/util/bitrate_helper.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

Future<void> showTranscodeSettingsPopup({
  required BuildContext context,
  required TranscodeDownloadModel current,
  required Function(TranscodeDownloadModel value) onChanged,
  Function? onClosed,

  /// Offers an "always use these settings" box. The download flow ticks it to
  /// stop being asked; the settings screen has no use for it.
  bool showAlwaysOption = false,
  Function(bool always)? onAlways,
}) async {
  await showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: TranscodeSettingsPopup(
            current: current,
            onChanged: onChanged,
            onClosed: onClosed,
            showAlwaysOption: showAlwaysOption,
            onAlways: onAlways,
          ),
        ),
      );
    },
  );
}

class TranscodeSettingsPopup extends StatefulWidget {
  final TranscodeDownloadModel current;
  final Function(TranscodeDownloadModel value) onChanged;
  final Function? onClosed;
  final bool showAlwaysOption;
  final Function(bool always)? onAlways;
  const TranscodeSettingsPopup({
    required this.current,
    required this.onChanged,
    this.onClosed,
    this.showAlwaysOption = false,
    this.onAlways,
    super.key,
  });

  @override
  State<TranscodeSettingsPopup> createState() => _TranscodeSettingsPopupState();
}

class _TranscodeSettingsPopupState extends State<TranscodeSettingsPopup> {
  late TranscodeDownloadModel currentModel = widget.current;
  bool alwaysUseThese = false;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        spacing: 16,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.localized.transcodeInfoTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Divider(),
          SingleChildScrollView(
            child: Column(
              children: [
                SettingsListTile(
                  label: Text(context.localized.enabled),
                  trailing: Switch(
                    value: currentModel.enabled,
                    onChanged: (value) {
                      setState(() {
                        currentModel = currentModel.copyWith(enabled: value);
                      });
                    },
                  ),
                ),
                SettingsListTileEnum(
                  label: Text(context.localized.bitrateLabel),
                  current: currentModel.maxBitrate.label(context),
                  itemBuilder: (context) {
                    return Bitrate.values
                        .where((element) => element != Bitrate.auto)
                        .map((e) => ItemActionButton(
                              label: Text(e.label(context)),
                              action: () {
                                setState(() {
                                  currentModel = currentModel.copyWith(maxBitrate: e);
                                });
                              },
                            ))
                        .toList();
                  },
                ),
                SettingsListTileEnum(
                  label: Text(context.localized.resolutionLabel),
                  current: currentModel.maxHeight.label,
                  itemBuilder: (context) {
                    return MaxHeight.values
                        .map((e) => ItemActionButton(
                              label: Text(e.label),
                              action: () {
                                setState(() {
                                  currentModel = currentModel.copyWith(maxHeight: e);
                                });
                              },
                            ))
                        .toList();
                  },
                ),
                SettingsListTileEnum(
                  label: Text(context.localized.videoCodecLabel),
                  current: currentModel.videoCodec.name,
                  itemBuilder: (context) {
                    return VideoCodec.values
                        .map((e) => ItemActionButton(
                              label: Text(e.name),
                              action: () {
                                setState(() {
                                  currentModel = currentModel.copyWith(videoCodec: e);
                                });
                              },
                            ))
                        .toList();
                  },
                ),
                SettingsListTileEnum(
                  label: Text(context.localized.audioCodecLabel),
                  current: currentModel.audioCodec.name,
                  itemBuilder: (context) {
                    return AudioCodec.values
                        .map((e) => ItemActionButton(
                              label: Text(e.name),
                              action: () {
                                setState(() {
                                  currentModel = currentModel.copyWith(audioCodec: e);
                                });
                              },
                            ))
                        .toList();
                  },
                ),
                SettingsListTileEnum(
                  label: Text(context.localized.containerLabel),
                  current: currentModel.container.name,
                  itemBuilder: (context) {
                    return VideoContainer.values
                        .map((e) => ItemActionButton(
                              label: Text(e.name),
                              action: () {
                                setState(() {
                                  currentModel = currentModel.copyWith(container: e);
                                });
                              },
                            ))
                        .toList();
                  },
                ),
              ],
            ),
          ),
          if (widget.showAlwaysOption)
            CheckboxListTile(
              value: alwaysUseThese,
              onChanged: (value) => setState(() => alwaysUseThese = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(context.localized.downloadQualityAlways),
              subtitle: Text(context.localized.downloadQualityAlwaysDesc),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  if (widget.onClosed != null) {
                    widget.onClosed!();
                  }
                  Navigator.of(context).pop();
                },
                child: Text(
                  context.localized.cancel,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  widget.onChanged(currentModel);
                  widget.onAlways?.call(alwaysUseThese);
                  Navigator.of(context).pop();
                },
                child: Text(context.localized.set),
              ),
            ],
          )
        ],
      ),
    );
  }
}
