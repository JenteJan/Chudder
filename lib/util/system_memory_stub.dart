/// The web build cannot tell how much memory the machine has left.
class SystemMemory {
  const SystemMemory({required this.totalBytes, required this.availableBytes});

  final int totalBytes;
  final int availableBytes;

  double get availableShare => totalBytes <= 0 ? 1 : availableBytes / totalBytes;

  static bool get supported => false;

  static SystemMemory? read() => null;
}
