/// The load-time benchmark's entry points. Everything is inert unless the app
/// was started with `--perf-bench=<config.json>`; see tool/perf/README.md.
library;

export 'package:chudder/perf_bench/perf_bench_stub.dart'
    if (dart.library.io) 'package:chudder/perf_bench/perf_bench_io.dart';
