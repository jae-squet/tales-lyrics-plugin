// lib/lyrics/lyrics_pack_manager.dart
//
// Manages the offline Whisper lyrics plugin bundle hosted on GitHub Releases.
//
// Bundle layout (lyrics_plugin_v1.zip):
//   ├── libwhisper_jni.so        ← native JNI bridge (~5 MB)
//   ├── ggml-base.bin            ← Whisper base model weights (~142 MB)
//   └── plugin_manifest.json     ← { "version": "1.0.0", "model": "base" }
//
// All files land in:
//   <appDocuments>/lyrics_pack/
//
// Nothing from this plugin is bundled in the APK.

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

class PackManifest {
  final String version;
  final String model;
  const PackManifest({required this.version, required this.model});

  factory PackManifest.fromJson(Map<String, dynamic> j) => PackManifest(
        version: j['version'] as String? ?? '0.0.0',
        model:   j['model']   as String? ?? 'base',
      );
}

class LyricsPackManager {
  // ── Configuration ─────────────────────────────────────────────────────────
  // Replace with your actual GitHub release URL before publishing.
  static const String _bundleUrl =
      'https://github.com/jae-squet/Tales-player-v1/releases/download/v1/lyrics_plugin_v1_arm64.zip';

  static const String _packFolder  = 'lyrics_pack';
  static const String _zipFileName = 'lyrics_plugin_v1.zip';
  static const String _soFileName  = 'libwhisper_jni.so';
  static const String _modelFile   = 'ggml-base.bin';
  static const String _manifestFile = 'plugin_manifest.json';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 20), // large file
  ));

  // ── Public paths ──────────────────────────────────────────────────────────

  Future<Directory> getPackDir() async {
    final base   = await getApplicationDocumentsDirectory();
    final folder = Directory('${base.path}/$_packFolder');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return folder;
  }

  Future<String> get soPath async {
    final dir = await getPackDir();
    return '${dir.path}/$_soFileName';
  }

  Future<String> get modelPath async {
    final dir = await getPackDir();
    return '${dir.path}/$_modelFile';
  }

  // ── Installation state ────────────────────────────────────────────────────

  /// Returns true only when BOTH the .so and the model weights are present
  /// and the manifest version matches what we expect.
  Future<bool> isInstalled() async {
    final dir = await getPackDir();
    final so     = File('${dir.path}/$_soFileName');
    final model  = File('${dir.path}/$_modelFile');
    final mf     = File('${dir.path}/$_manifestFile');

    if (!so.existsSync() || !model.existsSync()) return false;

    // Sanity-check: .so must be at least 1 MB, model at least 100 MB
    if (so.lengthSync()    < 1  * 1024 * 1024)  return false;
    if (model.lengthSync() < 100 * 1024 * 1024) return false;

    if (mf.existsSync()) {
      try {
        final manifest = PackManifest.fromJson(
          jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>,
        );
        return manifest.version.isNotEmpty;
      } catch (_) {}
    }
    return true; // files present but no manifest — acceptable
  }

  Future<PackManifest?> getInstalledManifest() async {
    final dir = await getPackDir();
    final mf  = File('${dir.path}/$_manifestFile');
    if (!mf.existsSync()) return null;
    try {
      return PackManifest.fromJson(
        jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Download ──────────────────────────────────────────────────────────────

  /// Downloads and installs the plugin bundle.
  /// [onProgress] receives (bytesReceived, totalBytes, phase).
  Future<void> downloadAndInstall({
    required void Function(int received, int total, String phase) onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir     = await getPackDir();
    final zipPath = '${dir.path}/$_zipFileName';

    // ── Step 1: Download ───────────────────────────────────────────────────
    onProgress(0, 1, 'Downloading lyrics plugin…');
    try {
      await _dio.download(
        _bundleUrl,
        zipPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          onProgress(received, total < 0 ? 150 * 1024 * 1024 : total, 'Downloading…');
        },
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw Exception('Download failed: ${e.message}');
    }

    // ── Step 2: Extract ────────────────────────────────────────────────────
    onProgress(1, 1, 'Installing plugin…');
    await _extract(zipPath, dir.path);

    // ── Step 3: Cleanup zip ────────────────────────────────────────────────
    final zipFile = File(zipPath);
    if (zipFile.existsSync()) zipFile.deleteSync();

    // ── Step 4: Verify ─────────────────────────────────────────────────────
    if (!await isInstalled()) {
      throw Exception(
        'Plugin installation failed: expected files were not found after extraction.',
      );
    }

    onProgress(1, 1, 'Plugin ready!');
  }

  Future<void> _extract(String zipPath, String destDir) async {
    final bytes   = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final entry in archive) {
      // Strip leading directory component if present
      final name = entry.name.replaceFirst(RegExp(r'^[^/]+/'), '');
      if (name.isEmpty) continue;

      final outPath = '$destDir/$name';

      if (entry.isFile) {
        final data    = entry.content as List<int>;
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(data);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
  }

  // ── Uninstall ─────────────────────────────────────────────────────────────

  Future<void> uninstall() async {
    final dir = await getPackDir();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  // ── Cache management ──────────────────────────────────────────────────────

  /// Returns the directory where generated .lrc files are cached.
  Future<Directory> getCacheDir() async {
    final dir = await getPackDir();
    final cache = Directory('${dir.path}/lrc_cache');
    if (!cache.existsSync()) cache.createSync(recursive: true);
    return cache;
  }

  Future<String> cachedLrcPath(String songId) async {
    final cache = await getCacheDir();
    return '${cache.path}/$songId.lrc';
  }

  Future<bool> hasCachedLrc(String songId) async {
    final path = await cachedLrcPath(songId);
    return File(path).existsSync();
  }

  Future<String?> readCachedLrc(String songId) async {
    final path = await cachedLrcPath(songId);
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }

  Future<void> saveLrcCache(String songId, String lrcContent) async {
    final path = await cachedLrcPath(songId);
    File(path).writeAsStringSync(lrcContent);
  }
}
