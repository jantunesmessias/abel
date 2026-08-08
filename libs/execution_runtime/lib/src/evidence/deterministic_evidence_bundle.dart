import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

final class EvidenceBundleBuildResult {
  const EvidenceBundleBuildResult({
    required this.path,
    required this.archiveDigest,
    required this.manifest,
    required this.size,
  });

  final String path;
  final Digest archiveDigest;
  final EvidenceBundleManifest manifest;
  final int size;
}

final class DeterministicEvidenceBundleRepository {
  const DeterministicEvidenceBundleRepository({
    this.maxEntries = 10000,
    this.maxEntryBytes = 512 * 1024 * 1024,
    this.maxTotalBytes = 512 * 1024 * 1024,
  });

  final int maxEntries;
  final int maxEntryBytes;
  final int maxTotalBytes;

  EvidenceBundleBuildResult build({
    required String releaseDirectory,
    required String outputPath,
  }) {
    if (!outputPath.endsWith('.evidence.zip')) {
      throw const FormatException('Bundle output must end with .evidence.zip');
    }
    final output = File(outputPath).absolute;
    if (output.existsSync() || Link(output.path).existsSync()) {
      throw FileSystemException('Bundle output already exists', output.path);
    }
    final directory = _safeDirectory(releaseDirectory);
    final source = _readReleaseDirectory(directory);
    final manifest = _manifest(source);
    final manifestBytes = utf8.encode(
      const JcsCanonicalizer().canonicalize(manifest.toJson()),
    );
    final archiveEntries = <String, List<int>>{
      ...source,
      'manifest.json': manifestBytes,
    };
    final archive = _StoredZipEncoder().encode(archiveEntries);
    if (archive.length > maxTotalBytes + 8 * 1024 * 1024) {
      throw const FormatException(
        'Encoded .evidence.zip exceeds archive limit',
      );
    }
    output.parent.createSync(recursive: true);
    final staging = File('${output.path}.new-$pid');
    if (staging.existsSync() || Link(staging.path).existsSync()) {
      throw FileSystemException(
        'Bundle staging path already exists',
        staging.path,
      );
    }
    try {
      staging.writeAsBytesSync(archive, flush: true);
      final verified = verify(staging.path);
      staging.renameSync(output.path);
      return EvidenceBundleBuildResult(
        path: output.path,
        archiveDigest: verified.archiveDigest,
        manifest: verified.manifest,
        size: archive.length,
      );
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
  }

  EvidenceBundleBuildResult verify(String bundlePath) {
    final file = File(bundlePath).absolute;
    if (Link(file.path).existsSync() || !file.existsSync()) {
      throw FileSystemException('Bundle is missing or linked', file.path);
    }
    final length = file.lengthSync();
    if (length <= 0 || length > maxTotalBytes + 8 * 1024 * 1024) {
      throw const FormatException('.evidence.zip size is invalid');
    }
    final bytes = file.readAsBytesSync();
    final entries = _StoredZipDecoder(
      maxEntries: maxEntries,
      maxEntryBytes: maxEntryBytes,
      maxTotalBytes: maxTotalBytes,
    ).decode(bytes);
    final manifestBytes = entries['manifest.json'];
    if (manifestBytes == null) {
      throw const FormatException('Bundle manifest.json is missing');
    }
    final manifestValue = jsonDecode(utf8.decode(manifestBytes));
    final manifest = EvidenceBundleManifest.fromJson(manifestValue);
    final canonical = utf8.encode(
      const JcsCanonicalizer().canonicalize(manifest.toJson()),
    );
    if (!_sameBytes(manifestBytes, canonical)) {
      throw const FormatException('Bundle manifest.json is not canonical JCS');
    }
    final payload = Map<String, List<int>>.of(entries)..remove('manifest.json');
    final declaredPaths = manifest.entries.map((entry) => entry.path).toSet();
    if (payload.length != declaredPaths.length ||
        !payload.keys.toSet().containsAll(declaredPaths)) {
      throw const FormatException(
        'Bundle manifest inventory differs from ZIP entries',
      );
    }
    for (final entry in manifest.entries) {
      final content = payload[entry.path]!;
      if (content.length != entry.size ||
          Digest.bytes(content) != entry.digest) {
        throw FormatException(
          'Bundle entry failed digest verification: ${entry.path}',
        );
      }
    }
    final releaseBundle = _validateReleaseEntries(payload);
    if (manifest.releaseDigest != releaseBundle.release.digest ||
        manifest.releaseBundleDigest != releaseBundle.digest) {
      throw const FormatException('Bundle manifest release identity mismatch');
    }
    return EvidenceBundleBuildResult(
      path: file.path,
      archiveDigest: Digest.bytes(bytes),
      manifest: manifest,
      size: bytes.length,
    );
  }

  Map<String, List<int>> _readReleaseDirectory(Directory root) {
    final output = <String, List<int>>{};
    var total = 0;
    final entities = root.listSync(recursive: true, followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entities) {
      if (entity is Link) {
        throw FileSystemException(
          'Release bundle contains a symlink',
          entity.path,
        );
      }
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: root.path)
          .replaceAll(p.separator, '/');
      _safeArchivePath(relative);
      if (output.length >= maxEntries || entity.lengthSync() > maxEntryBytes) {
        throw const FormatException('Release bundle entry limit exceeded');
      }
      final bytes = entity.readAsBytesSync();
      total += bytes.length;
      if (total > maxTotalBytes) {
        throw const FormatException('Release bundle total size exceeded');
      }
      output[relative] = bytes;
    }
    _validateReleaseEntries(output);
    return output;
  }

  EvidenceBundleManifest _manifest(Map<String, List<int>> entries) {
    final bundle = ReleaseBundle.fromJson(
      _decodeObject(entries['bundle.json'], 'bundle.json'),
    );
    final mediaTypes = <String, String>{
      'bundle.json': 'application/json',
      'release.json': 'application/vnd.distribution.release.v1+json',
      'publication.json': 'application/json',
      for (final artifact in bundle.artifacts)
        'blobs/sha256/${artifact.digest.value.substring('sha256:'.length)}':
            artifact.mediaType,
    };
    return EvidenceBundleManifest(
      releaseDigest: bundle.release.digest,
      releaseBundleDigest: bundle.digest,
      entries: <EvidenceBundleEntry>[
        for (final entry in entries.entries)
          EvidenceBundleEntry(
            path: entry.key,
            digest: Digest.bytes(entry.value),
            size: entry.value.length,
            mediaType: mediaTypes[entry.key] ?? 'application/octet-stream',
          ),
      ],
    );
  }

  ReleaseBundle _validateReleaseEntries(Map<String, List<int>> entries) {
    final bundle = ReleaseBundle.fromJson(
      _decodeObject(entries['bundle.json'], 'bundle.json'),
    );
    final release = Release.fromJson(
      _decodeObject(entries['release.json'], 'release.json'),
      expectedDigest: bundle.release.digest,
    );
    if (release.digest != bundle.release.digest) {
      throw const FormatException('bundle.json and release.json disagree');
    }
    _canonical(
      entries['bundle.json']!,
      bundle.toJson(),
      trailingNewline: true,
      path: 'bundle.json',
    );
    _canonical(
      entries['release.json']!,
      release.toJson(),
      trailingNewline: false,
      path: 'release.json',
    );
    _canonical(
      entries['publication.json'] ??
          (throw const FormatException('publication.json is missing')),
      PublicationView(release: release, includeSensitive: false).toJson(),
      trailingNewline: true,
      path: 'publication.json',
    );
    final expected = <String>{
      'bundle.json',
      'release.json',
      'publication.json',
    };
    for (final artifact in bundle.artifacts) {
      final path =
          'blobs/sha256/${artifact.digest.value.substring('sha256:'.length)}';
      expected.add(path);
      final bytes = entries[path];
      if (bytes == null ||
          bytes.length != artifact.size ||
          Digest.bytes(bytes) != artifact.digest) {
        throw FormatException(
          'Release artifact failed verification: ${artifact.digest.value}',
        );
      }
    }
    if (entries.length != expected.length ||
        !entries.keys.toSet().containsAll(expected)) {
      throw const FormatException(
        'Release bundle contains missing or unexpected files',
      );
    }
    return bundle;
  }

  Map<String, Object?> _decodeObject(List<int>? bytes, String path) {
    if (bytes == null) throw FormatException('$path is missing');
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must contain an object');
    }
    return value;
  }

  void _canonical(
    List<int> actual,
    Map<String, Object?> value, {
    required bool trailingNewline,
    required String path,
  }) {
    final text = const JcsCanonicalizer().canonicalize(value);
    final expected = utf8.encode(trailingNewline ? '$text\n' : text);
    if (!_sameBytes(actual, expected)) {
      throw FormatException('$path is not canonical JCS');
    }
  }
}

final class _ZipSourceEntry {
  const _ZipSourceEntry(
    this.name,
    this.nameBytes,
    this.bytes,
    this.crc,
    this.offset,
  );
  final String name;
  final List<int> nameBytes;
  final List<int> bytes;
  final int crc;
  final int offset;
}

final class _StoredZipEncoder {
  List<int> encode(Map<String, List<int>> source) {
    final output = BytesBuilder(copy: false);
    final entries = <_ZipSourceEntry>[];
    final names = source.keys.toList()..sort();
    for (final name in names) {
      _safeArchivePath(name);
      final nameBytes = utf8.encode(name);
      final bytes = source[name]!;
      final crc = _crc32(bytes);
      final offset = output.length;
      _u32(output, 0x04034b50);
      _u16(output, 20);
      _u16(output, 0x0800);
      _u16(output, 0);
      _u16(output, 0);
      _u16(output, 0x0021);
      _u32(output, crc);
      _u32(output, bytes.length);
      _u32(output, bytes.length);
      _u16(output, nameBytes.length);
      _u16(output, 0);
      output.add(nameBytes);
      output.add(bytes);
      entries.add(_ZipSourceEntry(name, nameBytes, bytes, crc, offset));
    }
    final centralOffset = output.length;
    for (final entry in entries) {
      _u32(output, 0x02014b50);
      _u16(output, 0x0314);
      _u16(output, 20);
      _u16(output, 0x0800);
      _u16(output, 0);
      _u16(output, 0);
      _u16(output, 0x0021);
      _u32(output, entry.crc);
      _u32(output, entry.bytes.length);
      _u32(output, entry.bytes.length);
      _u16(output, entry.nameBytes.length);
      _u16(output, 0);
      _u16(output, 0);
      _u16(output, 0);
      _u16(output, 0);
      _u32(output, 0x81a40000);
      _u32(output, entry.offset);
      output.add(entry.nameBytes);
    }
    final centralSize = output.length - centralOffset;
    _u32(output, 0x06054b50);
    _u16(output, 0);
    _u16(output, 0);
    _u16(output, entries.length);
    _u16(output, entries.length);
    _u32(output, centralSize);
    _u32(output, centralOffset);
    _u16(output, 0);
    return output.takeBytes();
  }
}

final class _StoredZipDecoder {
  const _StoredZipDecoder({
    required this.maxEntries,
    required this.maxEntryBytes,
    required this.maxTotalBytes,
  });
  final int maxEntries;
  final int maxEntryBytes;
  final int maxTotalBytes;

  Map<String, List<int>> decode(List<int> source) {
    final bytes = Uint8List.fromList(source);
    final data = ByteData.sublistView(bytes);
    final eocd = _findEocd(data);
    if (eocd + 22 != data.lengthInBytes) {
      throw const FormatException('ZIP contains trailing data');
    }
    if (_u16at(data, eocd + 4) != 0 ||
        _u16at(data, eocd + 6) != 0 ||
        _u16at(data, eocd + 20) != 0) {
      throw const FormatException('Multi-disk or commented ZIP is not allowed');
    }
    final entries = _u16at(data, eocd + 10);
    if (entries == 0 ||
        entries != _u16at(data, eocd + 8) ||
        entries > maxEntries) {
      throw const FormatException('ZIP entry count is invalid');
    }
    final centralSize = _u32at(data, eocd + 12);
    final centralOffset = _u32at(data, eocd + 16);
    if (centralOffset + centralSize != eocd) {
      throw const FormatException('ZIP central directory bounds are invalid');
    }
    var cursor = centralOffset;
    var total = 0;
    var expectedLocalOffset = 0;
    String? previousName;
    final output = <String, List<int>>{};
    for (var index = 0; index < entries; index += 1) {
      _bounds(data, cursor, 46);
      if (_u32at(data, cursor) != 0x02014b50) {
        throw const FormatException('ZIP central entry signature is invalid');
      }
      final flags = _u16at(data, cursor + 8);
      final method = _u16at(data, cursor + 10);
      final time = _u16at(data, cursor + 12);
      final date = _u16at(data, cursor + 14);
      final crc = _u32at(data, cursor + 16);
      final compressed = _u32at(data, cursor + 20);
      final uncompressed = _u32at(data, cursor + 24);
      final nameLength = _u16at(data, cursor + 28);
      final extraLength = _u16at(data, cursor + 30);
      final commentLength = _u16at(data, cursor + 32);
      final disk = _u16at(data, cursor + 34);
      final internalAttributes = _u16at(data, cursor + 36);
      final externalAttributes = _u32at(data, cursor + 38);
      final offset = _u32at(data, cursor + 42);
      if (_u16at(data, cursor + 4) != 0x0314 ||
          _u16at(data, cursor + 6) != 20 ||
          flags != 0x0800 ||
          method != 0 ||
          time != 0 ||
          date != 0x0021 ||
          compressed != uncompressed ||
          extraLength != 0 ||
          commentLength != 0 ||
          disk != 0 ||
          internalAttributes != 0 ||
          externalAttributes != 0x81a40000 ||
          offset != expectedLocalOffset ||
          uncompressed > maxEntryBytes) {
        throw const FormatException(
          'ZIP entry violates the deterministic stored profile',
        );
      }
      _bounds(data, cursor + 46, nameLength);
      final nameBytes = bytes.sublist(cursor + 46, cursor + 46 + nameLength);
      final name = utf8.decode(nameBytes, allowMalformed: false);
      _safeArchivePath(name);
      if (previousName != null && previousName.compareTo(name) >= 0) {
        throw const FormatException(
          'ZIP entries are not in canonical path order',
        );
      }
      previousName = name;
      if (output.containsKey(name)) {
        throw FormatException('Duplicate ZIP entry: $name');
      }
      _bounds(data, offset, 30);
      if (_u32at(data, offset) != 0x04034b50 ||
          _u16at(data, offset + 6) != flags ||
          _u16at(data, offset + 8) != method ||
          _u16at(data, offset + 10) != time ||
          _u16at(data, offset + 12) != date ||
          _u32at(data, offset + 14) != crc ||
          _u32at(data, offset + 18) != compressed ||
          _u32at(data, offset + 22) != uncompressed ||
          _u16at(data, offset + 26) != nameLength ||
          _u16at(data, offset + 28) != 0) {
        throw const FormatException(
          'ZIP local header differs from central directory',
        );
      }
      _bounds(data, offset + 30, nameLength + compressed);
      final localName = bytes.sublist(offset + 30, offset + 30 + nameLength);
      if (!_sameBytes(nameBytes, localName)) {
        throw const FormatException('ZIP entry names disagree');
      }
      final start = offset + 30 + nameLength;
      if (start + compressed > centralOffset) {
        throw const FormatException(
          'ZIP local entry overlaps the central directory',
        );
      }
      final content = bytes.sublist(start, start + compressed);
      if (_crc32(content) != crc) {
        throw FormatException('ZIP CRC mismatch: $name');
      }
      total += content.length;
      if (total > maxTotalBytes) {
        throw const FormatException('ZIP expanded size exceeds limit');
      }
      output[name] = content;
      expectedLocalOffset = start + compressed;
      cursor += 46 + nameLength;
    }
    if (cursor != eocd) {
      throw const FormatException('ZIP central directory entry count differs');
    }
    if (expectedLocalOffset != centralOffset) {
      throw const FormatException(
        'ZIP local entries contain gaps or trailing bytes',
      );
    }
    return output;
  }

  int _findEocd(ByteData data) {
    final start = data.lengthInBytes - 22;
    if (start < 0) throw const FormatException('ZIP is truncated');
    for (
      var offset = start;
      offset >= 0 && offset >= data.lengthInBytes - 65557;
      offset -= 1
    ) {
      if (_u32at(data, offset) == 0x06054b50) return offset;
    }
    throw const FormatException('ZIP end record is missing');
  }
}

void _safeArchivePath(String value) {
  final segments = value.split('/');
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.contains('\\') ||
      value.contains('\u0000') ||
      value.endsWith('/') ||
      segments.contains('..') ||
      segments.contains('.') ||
      segments.contains('')) {
    throw FormatException('Unsafe archive path: $value');
  }
}

Directory _safeDirectory(String value) {
  final directory = Directory(value).absolute;
  if (Link(directory.path).existsSync() || !directory.existsSync()) {
    throw FileSystemException(
      'Release directory is missing or linked',
      directory.path,
    );
  }
  return Directory(directory.resolveSymbolicLinksSync());
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _bounds(ByteData data, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > data.lengthInBytes) {
    throw const FormatException('ZIP structure is out of bounds');
  }
}

int _u16at(ByteData data, int offset) {
  _bounds(data, offset, 2);
  return data.getUint16(offset, Endian.little);
}

int _u32at(ByteData data, int offset) {
  _bounds(data, offset, 4);
  return data.getUint32(offset, Endian.little);
}

void _u16(BytesBuilder output, int value) =>
    output.add(<int>[value & 0xff, (value >> 8) & 0xff]);

void _u32(BytesBuilder output, int value) => output.add(<int>[
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
]);

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    var value = (crc ^ byte) & 0xff;
    for (var bit = 0; bit < 8; bit += 1) {
      value = (value & 1) != 0 ? (value >> 1) ^ 0xedb88320 : value >> 1;
    }
    crc = (crc >> 8) ^ value;
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
