import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:chudder/models/syncing/transcode_download_model.dart';
import 'package:chudder/screens/settings/settings_list_tile.dart';
import 'package:chudder/screens/shared/animated_fade_size.dart';
import 'package:chudder/util/bitrate_helper.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/size_formatting.dart';
import 'package:chudder/widgets/shared/item_actions.dart';

Future<void> showTranscodeSettingsPopup({
  required BuildContext context,
  required TranscodeDownloadModel current,
  required Function(TranscodeDownloadModel value) onChanged,
  Function? onClosed,

  /// Offers an "always use these settings" box. The download flow ticks it to
  /// stop being asked; the settings screen has no use for it.
  bool showAlwaysOption = false,
  Function(bool always)? onAlways,

  /// What is about to be downloaded, so each choice can say what it will
  /// take up. Without it the sizes are per hour.
  DownloadScope? scope,
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
            scope: scope,
          ),
        ),
      );
    },
  );
}

String _runtimeLabel(Duration duration) =>
    duration.inHours > 0 ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m' : '${duration.inMinutes}m';

/// Whether this device is one where storage is the thing to economise on.
bool get _isHandheld => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

class TranscodeSettingsPopup extends StatefulWidget {
  final TranscodeDownloadModel current;
  final Function(TranscodeDownloadModel value) onChanged;
  final Function? onClosed;
  final bool showAlwaysOption;
  final Function(bool always)? onAlways;
  final DownloadScope? scope;
  const TranscodeSettingsPopup({
    required this.current,
    required this.onChanged,
    this.onClosed,
    this.showAlwaysOption = false,
    this.onAlways,
    this.scope,
    super.key,
  });

  @override
  State<TranscodeSettingsPopup> createState() => _TranscodeSettingsPopupState();
}

class _TranscodeSettingsPopupState extends State<TranscodeSettingsPopup> {
  late TranscodeDownloadModel currentModel = widget.current;
  late DownloadQualityPreset preset = DownloadQualityPreset.of(widget.current);
  bool alwaysUseThese = false;

  void choose(DownloadQualityPreset value) {
    setState(() {
      preset = value;
      currentModel = switch (value) {
        DownloadQualityPreset.original => currentModel.copyWith(enabled: false),
        DownloadQualityPreset.custom => currentModel.copyWith(enabled: true),
        _ => value.model!,
      };
    });
  }

  /// What a choice comes to, in the words the list shows under its name.
  String? sizeFor(BuildContext context, DownloadQualityPreset value) {
    final runtime = widget.scope?.runtime;
    final perHour = runtime == null || runtime <= Duration.zero;
    final span = perHour ? const Duration(hours: 1) : runtime;
    final int? bytes = switch (value) {
      DownloadQualityPreset.original => perHour ? null : widget.scope?.originalBytes,
      DownloadQualityPreset.custom => currentModel.maxBitrate.bitRate != null
          ? estimateDownloadBytes(span, currentModel.maxBitrate.bitRate!)
          : null,
      _ => estimateDownloadBytes(span, value.model!.maxBitrate.bitRate!),
    };
    if (bytes == null || bytes <= 0) return null;
    final size = bytes.byteFormat;
    if (size == null) return null;
    return perHour ? context.localized.downloadQualityPerHour(size) : "~$size";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recommended = DownloadQualityPreset.recommended(phone: _isHandheld);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        spacing: 12,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  context.localized.downloadQualityTitle,
                  style: theme.textTheme.titleLarge,
                ),
                // What the sizes below are for, so "~4 GB" has a meaning.
                Text(
                  widget.scope != null
                      ? context.localized.downloadQualityScope(widget.scope!.count, _runtimeLabel(widget.scope!.runtime))
                      : context.localized.downloadQualityScopePerHour,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<DownloadQualityPreset>(
                    groupValue: preset,
                    onChanged: (value) {
                      if (value != null) choose(value);
                    },
                    child: Column(
                      children: DownloadQualityPreset.values.map((value) {
                        final size = sizeFor(context, value);
                        return RadioListTile<DownloadQualityPreset>(
                          value: value,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          title: Row(
                            spacing: 8,
                            children: [
                              Flexible(child: Text(value.label(context))),
                              if (value == recommended)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    context.localized.recommended,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            [value.description(context), if (size != null) size].join('  ·  '),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  AnimatedFadeSize(
                    child: preset == DownloadQualityPreset.custom ? _customControls(context) : const SizedBox.shrink(),
                  ),
                ],
              ),
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
                  style: TextStyle(color: theme.colorScheme.error),
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

  /// Every knob, for when none of the presets is it.
  Widget _customControls(BuildContext context) {
    return Column(
      children: [
        SettingsListTileEnum(
          label: Text(context.localized.bitrateLabel),
          current: currentModel.maxBitrate.label(context),
          itemBuilder: (context) {
            return Bitrate.values
                .where((element) => element != Bitrate.auto && element != Bitrate.original)
                .map((e) => ItemActionButton(
                      label: Text(e.label(context)),
                      action: () => setState(() => currentModel = currentModel.copyWith(maxBitrate: e)),
                    ))
                .toList();
          },
        ),
        SettingsListTileEnum(
          label: Text(context.localized.resolutionLabel),
          current: "${currentModel.maxHeight.label}p",
          itemBuilder: (context) {
            return MaxHeight.values
                .map((e) => ItemActionButton(
                      label: Text("${e.label}p"),
                      action: () => setState(() => currentModel = currentModel.copyWith(maxHeight: e)),
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
                      action: () => setState(() => currentModel = currentModel.copyWith(videoCodec: e)),
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
                      action: () => setState(() => currentModel = currentModel.copyWith(audioCodec: e)),
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
                      action: () => setState(() => currentModel = currentModel.copyWith(container: e)),
                    ))
                .toList();
          },
        ),
      ],
    );
  }
}
