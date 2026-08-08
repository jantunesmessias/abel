import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

const String projectionLayoutPreservingSwapProtocol = 'preserving-swap-v1';
const String projectionLayoutLinuxX64SwapProvider =
    'linux-x64.renameat2-exchange-v1';
const String _projectionLayoutSwapDirectory =
    '.dart_tool/workspace/experience-authoring/swap';

/// One Host-private, stable, rotating slot per authoritative source.
///
/// The slot is deliberately independent of a request/grant. It is never sent
/// over RPC and is retained after commit or rollback. Before the next WAL for
/// the same source is created, the Host replaces its contents from durable CAS.
String projectionLayoutPromotionRecoverySlot({
  required AuthoringSubjectRef subject,
  required String relativeSourcePath,
}) {
  if (!_validRelativePath(relativeSourcePath)) {
    throw ArgumentError('Invalid ProjectionLayout recovery slot authority');
  }
  final token = Digest.semantic(<String, Object?>{
    'subject': subject.toJson(),
    'destination': relativeSourcePath,
    'purpose': 'rotating-source-slot-v1',
  }).value.substring('sha256:'.length);
  return p.posix.join(_projectionLayoutSwapDirectory, '$token.slot');
}

enum ProjectionLayoutPreservingSwapFailureCode {
  unsupported,
  unsafeEntity,
  ioFailure,
  outcomeUnknown,
}

enum ProjectionLayoutPreservingSwapFsyncTarget {
  privateDirectoryParent,
  stagingFile,
  stagingParent,
  destinationFile,
  destinationParent,
}

typedef ProjectionLayoutPreservingSwapFsyncHook =
    void Function(ProjectionLayoutPreservingSwapFsyncTarget target);

/// Sanitized failure from the native preserving-swap boundary.
///
/// Paths and errno remain private diagnostics and are deliberately omitted
/// from [toString], RPC errors, journal records, and public result objects.
final class ProjectionLayoutPreservingSwapFailure implements Exception {
  const ProjectionLayoutPreservingSwapFailure.unsupported()
    : this._(ProjectionLayoutPreservingSwapFailureCode.unsupported);

  const ProjectionLayoutPreservingSwapFailure.outcomeUnknown()
    : this._(ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown);

  const ProjectionLayoutPreservingSwapFailure._(
    this.code, {
    this._diagnosticPath,
    this._diagnosticErrno,
  });

  final ProjectionLayoutPreservingSwapFailureCode code;
  final String? _diagnosticPath;
  final int? _diagnosticErrno;

  @override
  int get hashCode => Object.hash(code, _diagnosticPath, _diagnosticErrno);

  @override
  bool operator ==(Object other) =>
      other is ProjectionLayoutPreservingSwapFailure &&
      other.code == code &&
      other._diagnosticPath == _diagnosticPath &&
      other._diagnosticErrno == _diagnosticErrno;

  @override
  String toString() => 'ProjectionLayoutPreservingSwapFailure(${code.name})';
}

/// Exact pre-syscall source drift displaced and preserved by the exchange.
final class ProjectionLayoutSourceConflict implements Exception {
  const ProjectionLayoutSourceConflict({
    required this.expectedDigest,
    required this.observedDigest,
  });

  final Digest expectedDigest;
  final Digest observedDigest;

  @override
  String toString() => 'ProjectionLayoutSourceConflict';
}

final class ProjectionLayoutPreservingSwapResult {
  const ProjectionLayoutPreservingSwapResult({
    required this.providerKind,
    required this.installedDigest,
    required this.displacedDigest,
    required this.installedByteLength,
    required this.displacedByteLength,
    required this.installedMetadataDigest,
    required this.displacedMetadataDigest,
  });

  final String providerKind;
  final Digest installedDigest;
  final Digest displacedDigest;
  final int installedByteLength;
  final int displacedByteLength;
  final Digest installedMetadataDigest;
  final Digest displacedMetadataDigest;
}

final class ProjectionLayoutPreservingSwapObservation {
  const ProjectionLayoutPreservingSwapObservation({
    required this.providerKind,
    required this.destinationDigest,
    required this.stagingDigest,
    required this.destinationByteLength,
    required this.stagingByteLength,
    required this.destinationMetadataDigest,
    required this.stagingMetadataDigest,
  });

  final String providerKind;
  final Digest? destinationDigest;
  final Digest? stagingDigest;
  final int? destinationByteLength;
  final int? stagingByteLength;
  final Digest? destinationMetadataDigest;
  final Digest? stagingMetadataDigest;
}

final class ProjectionLayoutPrivateStageResult {
  const ProjectionLayoutPrivateStageResult({
    required this.providerKind,
    required this.digest,
    required this.byteLength,
    required this.sourceMetadataDigest,
  });

  final String providerKind;
  final Digest digest;
  final int byteLength;
  final Digest sourceMetadataDigest;
}

abstract interface class ProjectionLayoutPreservingSwapPrimitive {
  String get providerKind;

  bool get isSupported;

  ProjectionLayoutPrivateStageResult stage({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required List<int> bytes,
    required int maxBytes,
  });

  Uint8List readStaging({
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  });

  ProjectionLayoutPreservingSwapResult exchange({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required Digest expectedDestinationDigest,
    required Digest expectedStagingDigest,
    required Digest expectedDestinationMetadataDigest,
    required Digest expectedStagingMetadataDigest,
    required int maxBytes,
  });

  ProjectionLayoutPreservingSwapObservation observe({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  });
}

/// Linux x64 provider backed only by `renameat2(..., RENAME_EXCHANGE)`.
///
/// Source and rotating slot are resolved from separate no-follow directory
/// descriptors. The private slot directory must be owned by the current uid
/// with mode 0700. Slot files are regular single-link files owned by that uid
/// and inherit the authoritative source uid/gid and mode before exchange. Both
/// parent directories plus both files are flushed around every exchange.
/// Callers must persist their recovery WAL before invoking [exchange]. The
/// validated `renameat2` syscall is the filesystem linearization point: a
/// pre-syscall edit is displaced into the private slot and rejected, while an
/// edit after that syscall is a later external operation that this provider
/// preserves rather than trying to overwrite during journal commit. Abel
/// effects run under the workspace lock and require stable content/workspace
/// roots; both absolute roots are rebound immediately before the syscall and
/// before a success result. This is not a digest-CAS primitive against a
/// non-cooperating writer that mutates an already-open inode. Once the first
/// exchange is visible, any observed root/content ambiguity remains in the two
/// names under the durable WAL and is reported as outcome-unknown.
final class LinuxX64ProjectionLayoutPreservingSwap
    implements ProjectionLayoutPreservingSwapPrimitive {
  const LinuxX64ProjectionLayoutPreservingSwap({
    this.beforeExchangeSyscall,
    this.afterExchangeSyscall,
    this.beforeFsync,
  });

  /// Deterministic fault-injection seams for native boundary tests.
  /// Production composition must use the default null hooks.
  final void Function()? beforeExchangeSyscall;
  final void Function()? afterExchangeSyscall;
  final ProjectionLayoutPreservingSwapFsyncHook? beforeFsync;

  static final _LinuxSwapBindings? _bindings = _LinuxSwapBindings.tryLoad();

  @override
  String get providerKind => projectionLayoutLinuxX64SwapProvider;

  @override
  bool get isSupported =>
      ffi.Abi.current() == ffi.Abi.linuxX64 && _bindings != null;

  _LinuxSwapBindings get _requiredBindings {
    final bindings = _bindings;
    if (ffi.Abi.current() != ffi.Abi.linuxX64 || bindings == null) {
      throw const ProjectionLayoutPreservingSwapFailure._(
        ProjectionLayoutPreservingSwapFailureCode.unsupported,
      );
    }
    return bindings;
  }

  @override
  ProjectionLayoutPrivateStageResult stage({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required List<int> bytes,
    required int maxBytes,
  }) {
    _requireStageRequest(
      contentRoot: contentRoot,
      destinationRelativePath: destinationRelativePath,
      workspaceRoot: workspaceRoot,
      stagingRelativePath: stagingRelativePath,
      maxBytes: maxBytes,
      byteLength: bytes.length,
    );
    return _requiredBindings.stage(
      contentRoot: p.normalize(p.absolute(contentRoot)),
      destinationRelativePath: destinationRelativePath,
      workspaceRoot: p.normalize(p.absolute(workspaceRoot)),
      stagingRelativePath: stagingRelativePath,
      bytes: bytes,
      maxBytes: maxBytes,
      providerKind: providerKind,
      beforeFsync: beforeFsync,
    );
  }

  @override
  Uint8List readStaging({
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  }) {
    _requireStageRequest(
      workspaceRoot: workspaceRoot,
      stagingRelativePath: stagingRelativePath,
      maxBytes: maxBytes,
    );
    return _requiredBindings.readStaging(
      workspaceRoot: p.normalize(p.absolute(workspaceRoot)),
      stagingRelativePath: stagingRelativePath,
      maxBytes: maxBytes,
    );
  }

  @override
  ProjectionLayoutPreservingSwapResult exchange({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required Digest expectedDestinationDigest,
    required Digest expectedStagingDigest,
    required Digest expectedDestinationMetadataDigest,
    required Digest expectedStagingMetadataDigest,
    required int maxBytes,
  }) {
    _requireExchangeRequest(
      contentRoot: contentRoot,
      destinationRelativePath: destinationRelativePath,
      workspaceRoot: workspaceRoot,
      stagingRelativePath: stagingRelativePath,
      maxBytes: maxBytes,
    );
    return _requiredBindings.exchange(
      contentRoot: p.normalize(p.absolute(contentRoot)),
      destinationRelativePath: destinationRelativePath,
      workspaceRoot: p.normalize(p.absolute(workspaceRoot)),
      stagingRelativePath: stagingRelativePath,
      expectedDestinationDigest: expectedDestinationDigest,
      expectedStagingDigest: expectedStagingDigest,
      expectedDestinationMetadataDigest: expectedDestinationMetadataDigest,
      expectedStagingMetadataDigest: expectedStagingMetadataDigest,
      maxBytes: maxBytes,
      providerKind: providerKind,
      beforeExchangeSyscall: beforeExchangeSyscall,
      afterExchangeSyscall: afterExchangeSyscall,
      beforeFsync: beforeFsync,
    );
  }

  @override
  ProjectionLayoutPreservingSwapObservation observe({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  }) {
    _requireExchangeRequest(
      contentRoot: contentRoot,
      destinationRelativePath: destinationRelativePath,
      workspaceRoot: workspaceRoot,
      stagingRelativePath: stagingRelativePath,
      maxBytes: maxBytes,
    );
    return _requiredBindings.observe(
      contentRoot: p.normalize(p.absolute(contentRoot)),
      destinationRelativePath: destinationRelativePath,
      workspaceRoot: p.normalize(p.absolute(workspaceRoot)),
      stagingRelativePath: stagingRelativePath,
      maxBytes: maxBytes,
      providerKind: providerKind,
    );
  }

  void _requireStageRequest({
    String? contentRoot,
    String? destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
    int? byteLength,
  }) {
    final normalizedContent = contentRoot == null
        ? null
        : p.normalize(p.absolute(contentRoot));
    final normalizedRoot = p.normalize(p.absolute(workspaceRoot));
    if ((contentRoot == null) != (destinationRelativePath == null) ||
        normalizedContent != null && !p.isAbsolute(normalizedContent) ||
        !p.isAbsolute(normalizedRoot) ||
        maxBytes < 1 ||
        byteLength != null && byteLength > maxBytes ||
        destinationRelativePath != null &&
            !_validRelativePath(destinationRelativePath) ||
        !_validPrivateStagePath(stagingRelativePath)) {
      throw const ProjectionLayoutPreservingSwapFailure._(
        ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
      );
    }
  }

  void _requireExchangeRequest({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  }) {
    final normalizedContent = p.normalize(p.absolute(contentRoot));
    final normalizedWorkspace = p.normalize(p.absolute(workspaceRoot));
    if (!p.isAbsolute(normalizedContent) ||
        !p.isAbsolute(normalizedWorkspace) ||
        maxBytes < 1 ||
        !_validRelativePath(destinationRelativePath) ||
        !_validPrivateStagePath(stagingRelativePath)) {
      throw const ProjectionLayoutPreservingSwapFailure._(
        ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
      );
    }
  }
}

bool _validRelativePath(String value) {
  if (value.isEmpty || value.contains('\u0000') || p.posix.isAbsolute(value)) {
    return false;
  }
  final normalized = p.posix.normalize(value);
  return normalized == value &&
      normalized != '.' &&
      normalized != '..' &&
      !normalized.startsWith('../');
}

bool _validPrivateStagePath(String value) =>
    _validRelativePath(value) &&
    p.posix.dirname(value) == _projectionLayoutSwapDirectory &&
    p.posix.extension(value) == '.slot';

final class _LinuxSwapBindings {
  _LinuxSwapBindings(this.library)
    : open = library.lookupFunction<_OpenNative, _OpenDart>('open'),
      openAt = library.lookupFunction<_OpenAtNative, _OpenAtDart>('openat'),
      close = library.lookupFunction<_CloseNative, _CloseDart>('close'),
      fstat = library.lookupFunction<_FstatNative, _FstatDart>('fstat'),
      fstatAt = library.lookupFunction<_FstatAtNative, _FstatAtDart>('fstatat'),
      pread = library.lookupFunction<_PreadNative, _PreadDart>('pread'),
      pwrite = library.lookupFunction<_PwriteNative, _PwriteDart>('pwrite'),
      ftruncate = library.lookupFunction<_FtruncateNative, _FtruncateDart>(
        'ftruncate',
      ),
      fchmod = library.lookupFunction<_FchmodNative, _FchmodDart>('fchmod'),
      fchown = library.lookupFunction<_FchownNative, _FchownDart>('fchown'),
      fsync = library.lookupFunction<_FsyncNative, _FsyncDart>('fsync'),
      mkdirAt = library.lookupFunction<_MkdirAtNative, _MkdirAtDart>('mkdirat'),
      renameAt2 = library.lookupFunction<_RenameAt2Native, _RenameAt2Dart>(
        'renameat2',
      ),
      effectiveUserId = library.lookupFunction<_GeteuidNative, _GeteuidDart>(
        'geteuid',
      ),
      errnoLocation = library
          .lookupFunction<_ErrnoLocationNative, _ErrnoLocationDart>(
            '__errno_location',
          );

  static _LinuxSwapBindings? tryLoad() {
    if (ffi.Abi.current() != ffi.Abi.linuxX64 ||
        ffi.sizeOf<_LinuxStat>() != 144) {
      return null;
    }
    try {
      return _LinuxSwapBindings(ffi.DynamicLibrary.process());
    } on Object {
      return null;
    }
  }

  final ffi.DynamicLibrary library;
  final _OpenDart open;
  final _OpenAtDart openAt;
  final _CloseDart close;
  final _FstatDart fstat;
  final _FstatAtDart fstatAt;
  final _PreadDart pread;
  final _PwriteDart pwrite;
  final _FtruncateDart ftruncate;
  final _FchmodDart fchmod;
  final _FchownDart fchown;
  final _FsyncDart fsync;
  final _MkdirAtDart mkdirAt;
  final _RenameAt2Dart renameAt2;
  final _GeteuidDart effectiveUserId;
  final _ErrnoLocationDart errnoLocation;

  static const int _oReadOnly = 0;
  static const int _oReadWrite = 0x2;
  static const int _oCreate = 0x40;
  static const int _oExclusive = 0x80;
  static const int _oNonBlock = 0x800;
  static const int _oDirectory = 0x10000;
  static const int _oNoFollow = 0x20000;
  static const int _oCloseOnExec = 0x80000;
  static const int _atSymlinkNoFollow = 0x100;
  static const int _renameExchange = 0x2;
  static const int _regularFileMode = 0x8000;
  static const int _directoryMode = 0x4000;
  static const int _fileTypeMask = 0xf000;
  static const int _authoritativeModeMask = 0xfff; // 07777
  static const int _privateDirectoryPermissions = 0x1c0; // 0700
  static const int _privateFilePermissions = 0x180; // 0600
  static const Set<int> _unsupportedErrnos = <int>{18, 22, 38, 95};
  static const Set<int> _unsafeEntityErrnos = <int>{40}; // ELOOP

  ProjectionLayoutPrivateStageResult stage({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required List<int> bytes,
    required int maxBytes,
    required String providerKind,
    required ProjectionLayoutPreservingSwapFsyncHook? beforeFsync,
  }) {
    final descriptors = <int>[];
    Object? failure;
    StackTrace? failureStack;
    ProjectionLayoutPrivateStageResult? result;
    try {
      final contentRootAuthorityFd = _openDirectoryTree(
        contentRoot,
        descriptors,
      );
      final contentRootAuthority = _directoryStat(contentRootAuthorityFd);
      final workspaceRootAuthorityFd = _openDirectoryTree(
        workspaceRoot,
        descriptors,
      );
      final workspaceRootAuthority = _directoryStat(workspaceRootAuthorityFd);
      final sourceParentFd = _openSourceParentFromRoot(
        contentRootAuthorityFd,
        destinationRelativePath,
        descriptors,
      );
      final sourceFd = _openAtChecked(
        sourceParentFd,
        p.posix.basename(destinationRelativePath),
        _oReadOnly | _oNonBlock | _oNoFollow | _oCloseOnExec,
      );
      descriptors.add(sourceFd);
      final sourceBefore = _authoritativeSourceStat(
        sourceFd,
        maxBytes: maxBytes,
      );
      final parentFd = _openPrivateStageParentFromRoot(
        workspaceRootAuthorityFd,
        descriptors,
        create: true,
        beforeFsync: beforeFsync,
      )!;
      if (_directoryStat(sourceParentFd).device !=
          _privateDirectoryStat(parentFd).device) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.unsupported,
        );
      }
      final name = p.posix.basename(stagingRelativePath);
      var stageFd = _openAtOptional(
        parentFd,
        name,
        _oReadWrite | _oNonBlock | _oNoFollow | _oCloseOnExec,
      );
      stageFd ??= _openAtCreateExclusive(
        parentFd,
        name,
        _oReadWrite |
            _oCreate |
            _oExclusive |
            _oNonBlock |
            _oNoFollow |
            _oCloseOnExec,
        _privateFilePermissions,
      );
      descriptors.add(stageFd);
      final stageBefore = _privateOwnedRegularSingleLinkStat(
        stageFd,
        maxBytes: maxBytes,
      );
      if (_sameInode(sourceBefore, stageBefore)) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
        );
      }
      if (ftruncate(stageFd, 0) != 0) _throwErrno(name, _errno);
      _writeAll(stageFd, bytes);
      if (ftruncate(stageFd, bytes.length) != 0) {
        _throwErrno(name, _errno);
      }
      if (fchown(stageFd, sourceBefore.userId, sourceBefore.groupId) != 0) {
        _throwErrno(name, _errno);
      }
      if (fchmod(stageFd, sourceBefore.mode & _authoritativeModeMask) != 0) {
        _throwErrno(name, _errno);
      }
      _fsyncChecked(
        stageFd,
        target: ProjectionLayoutPreservingSwapFsyncTarget.stagingFile,
        beforeFsync: beforeFsync,
      );
      final sourceAfter = _authoritativeSourceStat(
        sourceFd,
        maxBytes: maxBytes,
      );
      if (!_sameStableFile(sourceBefore, sourceAfter)) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.ioFailure,
        );
      }
      final stat = _privateOwnedRegularSingleLinkStat(
        stageFd,
        maxBytes: maxBytes,
      );
      if (!_sameAuthoritativeMetadata(stat, sourceAfter)) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
        );
      }
      final observed = _readStable(stageFd, stat, maxBytes: maxBytes);
      if (!_bytesEqual(observed, bytes)) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.ioFailure,
        );
      }
      _fsyncChecked(
        parentFd,
        target: ProjectionLayoutPreservingSwapFsyncTarget.stagingParent,
        beforeFsync: beforeFsync,
      );
      final rebound = _readEntryStatAt(parentFd, name);
      final finalStat = _privateOwnedRegularSingleLinkStat(
        stageFd,
        maxBytes: maxBytes,
      );
      if (!_sameRawEntryIdentity(rebound, finalStat) ||
          !_sameAuthoritativeMetadata(finalStat, sourceAfter)) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.ioFailure,
        );
      }
      final finalObserved = _readStable(stageFd, finalStat, maxBytes: maxBytes);
      if (!_bytesEqual(finalObserved, bytes)) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.ioFailure,
        );
      }
      _requireDirectoryTreeRebound(contentRoot, contentRootAuthority);
      _requireDirectoryTreeRebound(workspaceRoot, workspaceRootAuthority);
      result = ProjectionLayoutPrivateStageResult(
        providerKind: providerKind,
        digest: Digest.bytes(finalObserved),
        byteLength: finalObserved.length,
        sourceMetadataDigest: _authoritativeMetadataDigest(sourceAfter),
      );
    } on Object catch (error, stackTrace) {
      failure = _sanitize(error);
      failureStack = stackTrace;
    }
    _finishDescriptors(
      descriptors,
      failure: failure,
      failureStack: failureStack,
    );
    return result!;
  }

  Uint8List readStaging({
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  }) {
    final descriptors = <int>[];
    Object? failure;
    StackTrace? failureStack;
    Uint8List? result;
    try {
      final workspaceRootAuthorityFd = _openDirectoryTree(
        workspaceRoot,
        descriptors,
      );
      final workspaceRootAuthority = _directoryStat(workspaceRootAuthorityFd);
      final parentFd = _openPrivateStageParentFromRoot(
        workspaceRootAuthorityFd,
        descriptors,
        create: false,
      );
      if (parentFd == null) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
        );
      }
      final stageFd = _openAtChecked(
        parentFd,
        p.posix.basename(stagingRelativePath),
        _oReadOnly | _oNonBlock | _oNoFollow | _oCloseOnExec,
      );
      descriptors.add(stageFd);
      result = _readStable(
        stageFd,
        _privateOwnedRegularSingleLinkStat(stageFd, maxBytes: maxBytes),
        maxBytes: maxBytes,
      );
      _requireDirectoryTreeRebound(workspaceRoot, workspaceRootAuthority);
    } on Object catch (error, stackTrace) {
      failure = _sanitize(error);
      failureStack = stackTrace;
    }
    _finishDescriptors(
      descriptors,
      failure: failure,
      failureStack: failureStack,
    );
    return result!;
  }

  ProjectionLayoutPreservingSwapResult exchange({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required Digest expectedDestinationDigest,
    required Digest expectedStagingDigest,
    required Digest expectedDestinationMetadataDigest,
    required Digest expectedStagingMetadataDigest,
    required int maxBytes,
    required String providerKind,
    required void Function()? beforeExchangeSyscall,
    required void Function()? afterExchangeSyscall,
    required ProjectionLayoutPreservingSwapFsyncHook? beforeFsync,
  }) {
    final descriptors = <int>[];
    Object? failure;
    StackTrace? failureStack;
    ProjectionLayoutPreservingSwapResult? result;
    var exchanged = false;
    var restoredAfterFailure = false;
    var leaveExchangedForInjectedInterruption = false;
    var postSwapCallbackBoundaryCrossed = false;
    var mustPreserveExchangedPair = false;
    int? destinationParentFd;
    int? stagingParentFd;
    int? destinationFd;
    int? stagingFd;
    String? destinationName;
    String? stagingName;
    _LinuxFileStat? beforeDestination;
    _LinuxFileStat? beforeStaging;
    try {
      final contentRootAuthorityFd = _openDirectoryTree(
        contentRoot,
        descriptors,
      );
      final contentRootAuthority = _directoryStat(contentRootAuthorityFd);
      final workspaceRootAuthorityFd = _openDirectoryTree(
        workspaceRoot,
        descriptors,
      );
      final workspaceRootAuthority = _directoryStat(workspaceRootAuthorityFd);
      destinationParentFd = _openSourceParentFromRoot(
        contentRootAuthorityFd,
        destinationRelativePath,
        descriptors,
      );
      stagingParentFd = _openPrivateStageParentFromRoot(
        workspaceRootAuthorityFd,
        descriptors,
        create: false,
      );
      if (stagingParentFd == null ||
          _directoryStat(destinationParentFd).device !=
              _privateDirectoryStat(stagingParentFd).device) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.unsupported,
        );
      }
      destinationName = p.posix.basename(destinationRelativePath);
      stagingName = p.posix.basename(stagingRelativePath);
      destinationFd = _openAtChecked(
        destinationParentFd,
        destinationName,
        _oReadOnly | _oNonBlock | _oNoFollow | _oCloseOnExec,
      );
      descriptors.add(destinationFd);
      stagingFd = _openAtChecked(
        stagingParentFd,
        stagingName,
        _oReadOnly | _oNonBlock | _oNoFollow | _oCloseOnExec,
      );
      descriptors.add(stagingFd);
      beforeDestination = _authoritativeSourceStat(
        destinationFd,
        maxBytes: maxBytes,
      );
      beforeStaging = _privateOwnedRegularSingleLinkStat(
        stagingFd,
        maxBytes: maxBytes,
      );
      if (_authoritativeMetadataDigest(beforeDestination) !=
              expectedDestinationMetadataDigest ||
          _authoritativeMetadataDigest(beforeStaging) !=
              expectedStagingMetadataDigest) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
        );
      }
      final beforeDestinationBytes = _readStable(
        destinationFd,
        beforeDestination,
        maxBytes: maxBytes,
      );
      final beforeStagingBytes = _readStable(
        stagingFd,
        beforeStaging,
        maxBytes: maxBytes,
      );
      if (Digest.bytes(beforeDestinationBytes) != expectedDestinationDigest ||
          Digest.bytes(beforeStagingBytes) != expectedStagingDigest) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.ioFailure,
        );
      }
      _fsyncChecked(
        stagingFd,
        target: ProjectionLayoutPreservingSwapFsyncTarget.stagingFile,
        beforeFsync: beforeFsync,
      );
      _fsyncChecked(
        destinationFd,
        target: ProjectionLayoutPreservingSwapFsyncTarget.destinationFile,
        beforeFsync: beforeFsync,
      );
      beforeExchangeSyscall?.call();
      final preExchangeDestination = _authoritativeSourceStat(
        destinationFd,
        maxBytes: maxBytes,
      );
      final preExchangeStaging = _privateOwnedRegularSingleLinkStat(
        stagingFd,
        maxBytes: maxBytes,
      );
      final preExchangeDestinationPath = _readEntryStatAt(
        destinationParentFd,
        destinationName,
      );
      final preExchangeStagingPath = _readEntryStatAt(
        stagingParentFd,
        stagingName,
      );
      if (!_sameRawEntryIdentity(
            preExchangeDestinationPath,
            preExchangeDestination,
          ) ||
          !_sameRawEntryIdentity(preExchangeStagingPath, preExchangeStaging)) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
        );
      }
      final preExchangeDestinationDigest = Digest.bytes(
        _readStable(destinationFd, preExchangeDestination, maxBytes: maxBytes),
      );
      final preExchangeStagingDigest = Digest.bytes(
        _readStable(stagingFd, preExchangeStaging, maxBytes: maxBytes),
      );
      if (preExchangeDestinationDigest != expectedDestinationDigest) {
        throw ProjectionLayoutSourceConflict(
          expectedDigest: expectedDestinationDigest,
          observedDigest: preExchangeDestinationDigest,
        );
      }
      if (!_sameStableFile(beforeDestination, preExchangeDestination) ||
          _authoritativeMetadataDigest(preExchangeDestination) !=
              expectedDestinationMetadataDigest ||
          preExchangeStagingDigest != expectedStagingDigest ||
          !_sameStableFile(beforeStaging, preExchangeStaging) ||
          _authoritativeMetadataDigest(preExchangeStaging) !=
              expectedStagingMetadataDigest) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.ioFailure,
        );
      }
      _requireDirectoryTreeRebound(contentRoot, contentRootAuthority);
      _requireDirectoryTreeRebound(workspaceRoot, workspaceRootAuthority);
      _renameExchangeChecked(
        destinationParentFd,
        destinationName,
        stagingParentFd,
        stagingName,
      );
      exchanged = true;
      if (afterExchangeSyscall != null) {
        postSwapCallbackBoundaryCrossed = true;
        try {
          afterExchangeSyscall();
        } on Object {
          leaveExchangedForInjectedInterruption = true;
          throw const _InjectedPostSwapInterruption();
        }
      }
      if (beforeFsync != null) postSwapCallbackBoundaryCrossed = true;
      _fsyncChecked(
        destinationParentFd,
        target: ProjectionLayoutPreservingSwapFsyncTarget.destinationParent,
        beforeFsync: beforeFsync,
      );
      _fsyncChecked(
        stagingParentFd,
        target: ProjectionLayoutPreservingSwapFsyncTarget.stagingParent,
        beforeFsync: beforeFsync,
      );

      // The pre-opened FDs stay attached to the exact inodes across
      // renameat2. Re-read the candidate inode after the syscall: an in-place
      // mutation in the pre-syscall hook must never be accepted merely because
      // device/inode/mode still match.
      final installedStat = _authoritativeSourceStat(
        stagingFd,
        maxBytes: maxBytes,
      );
      final installed = _readStable(
        stagingFd,
        installedStat,
        maxBytes: maxBytes,
      );
      if (Digest.bytes(installed) != expectedStagingDigest ||
          _authoritativeMetadataDigest(installedStat) !=
              expectedStagingMetadataDigest) {
        mustPreserveExchangedPair = true;
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
        );
      }
      final displacedStat = _authoritativeSourceStat(
        destinationFd,
        maxBytes: maxBytes,
      );
      final displaced = _readStable(
        destinationFd,
        displacedStat,
        maxBytes: maxBytes,
      );
      if (_authoritativeMetadataDigest(displacedStat) !=
          expectedDestinationMetadataDigest) {
        mustPreserveExchangedPair = true;
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
        );
      }
      final displacedDigest = Digest.bytes(displaced);
      if (displacedDigest != expectedDestinationDigest) {
        if (postSwapCallbackBoundaryCrossed) {
          mustPreserveExchangedPair = true;
          throw const ProjectionLayoutPreservingSwapFailure._(
            ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
          );
        }
        mustPreserveExchangedPair = true;
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
        );
      }
      final installedPathStat = _readEntryStatAt(
        destinationParentFd,
        destinationName,
      );
      final displacedPathStat = _readEntryStatAt(stagingParentFd, stagingName);
      if (!_isRegularSingleLink(displacedPathStat)) {
        mustPreserveExchangedPair = true;
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
        );
      }
      if (!_sameRawEntryIdentity(installedPathStat, installedStat) ||
          !_sameRawEntryIdentity(displacedPathStat, displacedStat)) {
        mustPreserveExchangedPair = true;
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
        );
      }
      try {
        _requireDirectoryTreeRebound(contentRoot, contentRootAuthority);
        _requireDirectoryTreeRebound(workspaceRoot, workspaceRootAuthority);
      } on Object {
        mustPreserveExchangedPair = true;
        rethrow;
      }
      result = ProjectionLayoutPreservingSwapResult(
        providerKind: providerKind,
        installedDigest: Digest.bytes(installed),
        displacedDigest: displacedDigest,
        installedByteLength: installed.length,
        displacedByteLength: displaced.length,
        installedMetadataDigest: _authoritativeMetadataDigest(installedStat),
        displacedMetadataDigest: _authoritativeMetadataDigest(displacedStat),
      );
    } on Object catch (error, stackTrace) {
      failure = _sanitize(error);
      failureStack = stackTrace;
      if (exchanged &&
          !leaveExchangedForInjectedInterruption &&
          !postSwapCallbackBoundaryCrossed &&
          !mustPreserveExchangedPair) {
        try {
          final rawDestination = _readEntryStatAt(
            destinationParentFd!,
            destinationName!,
          );
          final rawStaging = _readEntryStatAt(stagingParentFd!, stagingName!);
          final candidateFdStat = _readStat(stagingFd!);
          final originalFdStat = _readStat(destinationFd!);
          final candidateDigest = Digest.bytes(
            _readStable(stagingFd, candidateFdStat, maxBytes: maxBytes),
          );
          final originalDigest = Digest.bytes(
            _readStable(destinationFd, originalFdStat, maxBytes: maxBytes),
          );
          if (!_sameRawEntryIdentity(rawDestination, candidateFdStat) ||
              !_sameRawEntryIdentity(rawStaging, originalFdStat) ||
              candidateDigest != expectedStagingDigest ||
              originalDigest != expectedDestinationDigest ||
              _authoritativeMetadataDigest(candidateFdStat) !=
                  expectedStagingMetadataDigest ||
              _authoritativeMetadataDigest(originalFdStat) !=
                  expectedDestinationMetadataDigest) {
            throw const ProjectionLayoutPreservingSwapFailure._(
              ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
            );
          }
          // The slot directory is Host-private (0700) and production has no
          // hook between the syscall and this check. Under that invariant, an
          // unexpected entry in the slot is the source entry displaced by the
          // first exchange. Swap it back without opening/following it, then
          // validate both raw identities. A post-syscall test hook disables
          // this inference and leaves both names for recovery instead.
          _renameExchangeChecked(
            destinationParentFd,
            destinationName,
            stagingParentFd,
            stagingName,
          );
          _fsyncChecked(
            destinationParentFd,
            target: ProjectionLayoutPreservingSwapFsyncTarget.destinationParent,
            beforeFsync: beforeFsync,
          );
          _fsyncChecked(
            stagingParentFd,
            target: ProjectionLayoutPreservingSwapFsyncTarget.stagingParent,
            beforeFsync: beforeFsync,
          );
          final restoredDestination = _readEntryStatAt(
            destinationParentFd,
            destinationName,
          );
          final restoredStaging = _readEntryStatAt(
            stagingParentFd,
            stagingName,
          );
          if (!_sameRawEntryIdentity(restoredDestination, rawStaging) ||
              !_sameRawEntryIdentity(restoredStaging, rawDestination)) {
            throw const ProjectionLayoutPreservingSwapFailure._(
              ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
            );
          }
          restoredAfterFailure = true;
        } on Object {
          failure = const ProjectionLayoutPreservingSwapFailure._(
            ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
          );
          failureStack = StackTrace.current;
        }
      } else if (leaveExchangedForInjectedInterruption ||
          exchanged &&
              (postSwapCallbackBoundaryCrossed || mustPreserveExchangedPair)) {
        failure = const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
        );
        failureStack = StackTrace.current;
      }
      if (exchanged &&
          !restoredAfterFailure &&
          failure is! ProjectionLayoutPreservingSwapFailure) {
        failure = const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
        );
        failureStack = StackTrace.current;
      }
    }
    _finishDescriptors(
      descriptors,
      failure: failure,
      failureStack: failureStack,
      successfulCloseFailureCode:
          ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
    );
    return result!;
  }

  ProjectionLayoutPreservingSwapObservation observe({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
    required String providerKind,
  }) {
    final descriptors = <int>[];
    Object? failure;
    StackTrace? failureStack;
    ProjectionLayoutPreservingSwapObservation? result;
    try {
      final contentRootAuthorityFd = _openDirectoryTree(
        contentRoot,
        descriptors,
      );
      final contentRootAuthority = _directoryStat(contentRootAuthorityFd);
      final workspaceRootAuthorityFd = _openDirectoryTree(
        workspaceRoot,
        descriptors,
      );
      final workspaceRootAuthority = _directoryStat(workspaceRootAuthorityFd);
      final destinationParentFd = _openSourceParentFromRoot(
        contentRootAuthorityFd,
        destinationRelativePath,
        descriptors,
      );
      final stagingParentFd = _openPrivateStageParentFromRoot(
        workspaceRootAuthorityFd,
        descriptors,
        create: false,
      );
      final destinationFd = _openAtOptional(
        destinationParentFd,
        p.posix.basename(destinationRelativePath),
        _oReadOnly | _oNonBlock | _oNoFollow | _oCloseOnExec,
      );
      if (destinationFd != null) descriptors.add(destinationFd);
      final stagingFd = stagingParentFd == null
          ? null
          : _openAtOptional(
              stagingParentFd,
              p.posix.basename(stagingRelativePath),
              _oReadOnly | _oNonBlock | _oNoFollow | _oCloseOnExec,
            );
      if (stagingFd != null) descriptors.add(stagingFd);
      final destinationStat = destinationFd == null
          ? null
          : _authoritativeSourceStat(destinationFd, maxBytes: maxBytes);
      final stagingStat = stagingFd == null
          ? null
          : _privateOwnedRegularSingleLinkStat(stagingFd, maxBytes: maxBytes);
      final destinationBytes = destinationFd == null
          ? null
          : _readStable(destinationFd, destinationStat!, maxBytes: maxBytes);
      final stagingBytes = stagingFd == null
          ? null
          : _readStable(stagingFd, stagingStat!, maxBytes: maxBytes);
      _requireDirectoryTreeRebound(contentRoot, contentRootAuthority);
      _requireDirectoryTreeRebound(workspaceRoot, workspaceRootAuthority);
      result = ProjectionLayoutPreservingSwapObservation(
        providerKind: providerKind,
        destinationDigest: destinationBytes == null
            ? null
            : Digest.bytes(destinationBytes),
        stagingDigest: stagingBytes == null ? null : Digest.bytes(stagingBytes),
        destinationByteLength: destinationBytes?.length,
        stagingByteLength: stagingBytes?.length,
        destinationMetadataDigest: destinationStat == null
            ? null
            : _authoritativeMetadataDigest(destinationStat),
        stagingMetadataDigest: stagingStat == null
            ? null
            : _authoritativeMetadataDigest(stagingStat),
      );
    } on Object catch (error, stackTrace) {
      failure = _sanitize(error);
      failureStack = stackTrace;
    }
    _finishDescriptors(
      descriptors,
      failure: failure,
      failureStack: failureStack,
    );
    return result!;
  }

  int _openSourceParentFromRoot(
    int contentRootFd,
    String destinationRelativePath,
    List<int> descriptors,
  ) {
    var directoryFd = contentRootFd;
    final parent = p.posix.dirname(destinationRelativePath);
    if (parent == '.') return directoryFd;
    for (final segment in p.posix.split(parent)) {
      if (segment == '.' || segment.isEmpty) continue;
      final next = _openAtChecked(
        directoryFd,
        segment,
        _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
      );
      descriptors.add(next);
      directoryFd = next;
    }
    return directoryFd;
  }

  int? _openPrivateStageParentFromRoot(
    int workspaceRootFd,
    List<int> descriptors, {
    required bool create,
    ProjectionLayoutPreservingSwapFsyncHook? beforeFsync,
  }) {
    var directoryFd = workspaceRootFd;
    final segments = p.posix.split(_projectionLayoutSwapDirectory);
    for (var index = 0; index < segments.length; index += 1) {
      final segment = segments[index];
      var next = _openAtOptional(
        directoryFd,
        segment,
        _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
      );
      if (next == null) {
        if (!create) return null;
        _mkdirAtChecked(directoryFd, segment, _privateDirectoryPermissions);
        next = _openAtChecked(
          directoryFd,
          segment,
          _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
        );
      }
      descriptors.add(next);
      if (create) {
        // A previous interrupted stage may have created this visible dirent
        // without durably flushing its parent. Re-fence every component.
        _fsyncChecked(
          directoryFd,
          target:
              ProjectionLayoutPreservingSwapFsyncTarget.privateDirectoryParent,
          beforeFsync: beforeFsync,
        );
      }
      directoryFd = next;
      if (index == segments.length - 1) {
        _privateDirectoryStat(directoryFd);
      }
    }
    return directoryFd;
  }

  int _openDirectoryTree(String absolutePath, List<int> descriptors) {
    var current = _openChecked(
      '/',
      _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
    );
    descriptors.add(current);
    for (final segment in p.posix.split(absolutePath)) {
      if (segment == '/' || segment == '.' || segment.isEmpty) continue;
      final next = _openAtChecked(
        current,
        segment,
        _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
      );
      descriptors.add(next);
      current = next;
    }
    return current;
  }

  void _requireDirectoryTreeRebound(
    String absolutePath,
    _LinuxFileStat expectedRoot,
  ) {
    final descriptors = <int>[];
    Object? failure;
    StackTrace? failureStack;
    try {
      final reboundFd = _openDirectoryTree(absolutePath, descriptors);
      final rebound = _directoryStat(reboundFd);
      if (!_sameRawEntryIdentity(rebound, expectedRoot)) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.ioFailure,
        );
      }
    } on Object catch (error, stackTrace) {
      failure = _sanitize(error);
      failureStack = stackTrace;
    }
    _finishDescriptors(
      descriptors,
      failure: failure,
      failureStack: failureStack,
    );
  }

  int _openChecked(String path, int flags) {
    final pointer = path.toNativeUtf8(allocator: calloc);
    try {
      final descriptor = open(pointer, flags, 0);
      if (descriptor < 0) _throwErrno(path, _errno);
      return descriptor;
    } finally {
      calloc.free(pointer);
    }
  }

  int _openAtChecked(int directoryFd, String name, int flags) {
    final pointer = name.toNativeUtf8(allocator: calloc);
    try {
      final descriptor = openAt(directoryFd, pointer, flags, 0);
      if (descriptor < 0) _throwErrno(name, _errno);
      return descriptor;
    } finally {
      calloc.free(pointer);
    }
  }

  int _openAtCreateExclusive(
    int directoryFd,
    String name,
    int flags,
    int mode,
  ) {
    final pointer = name.toNativeUtf8(allocator: calloc);
    try {
      final descriptor = openAt(directoryFd, pointer, flags, mode);
      if (descriptor < 0) _throwErrno(name, _errno);
      return descriptor;
    } finally {
      calloc.free(pointer);
    }
  }

  int? _openAtOptional(int directoryFd, String name, int flags) {
    final pointer = name.toNativeUtf8(allocator: calloc);
    try {
      final descriptor = openAt(directoryFd, pointer, flags, 0);
      if (descriptor >= 0) return descriptor;
      final errno = _errno;
      if (errno == 2) return null;
      _throwErrno(name, errno);
    } finally {
      calloc.free(pointer);
    }
  }

  void _mkdirAtChecked(int directoryFd, String name, int mode) {
    final pointer = name.toNativeUtf8(allocator: calloc);
    try {
      if (mkdirAt(directoryFd, pointer, mode) != 0) {
        final errno = _errno;
        if (errno != 17) _throwErrno(name, errno);
      }
    } finally {
      calloc.free(pointer);
    }
  }

  void _renameExchangeChecked(
    int destinationParentFd,
    String destinationName,
    int stagingParentFd,
    String stagingName,
  ) {
    final destinationPointer = destinationName.toNativeUtf8(allocator: calloc);
    final stagingPointer = stagingName.toNativeUtf8(allocator: calloc);
    try {
      if (renameAt2(
            destinationParentFd,
            destinationPointer,
            stagingParentFd,
            stagingPointer,
            _renameExchange,
          ) !=
          0) {
        final errno = _errno;
        if (_unsupportedErrnos.contains(errno)) {
          throw ProjectionLayoutPreservingSwapFailure._(
            ProjectionLayoutPreservingSwapFailureCode.unsupported,
            diagnosticErrno: errno,
          );
        }
        _throwErrno(null, errno);
      }
    } finally {
      calloc.free(stagingPointer);
      calloc.free(destinationPointer);
    }
  }

  void _writeAll(int descriptor, List<int> bytes) {
    if (bytes.isEmpty) return;
    final pointer = calloc<ffi.Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final count = pwrite(
          descriptor,
          (pointer + offset).cast(),
          bytes.length - offset,
          offset,
        );
        if (count < 0 && _errno == 4) continue;
        if (count <= 0) _throwErrno(null, count < 0 ? _errno : 5);
        offset += count;
      }
    } finally {
      calloc.free(pointer);
    }
  }

  void _fsyncChecked(
    int descriptor, {
    required ProjectionLayoutPreservingSwapFsyncTarget target,
    required ProjectionLayoutPreservingSwapFsyncHook? beforeFsync,
  }) {
    beforeFsync?.call(target);
    if (fsync(descriptor) != 0) _throwErrno(null, _errno);
  }

  _LinuxFileStat _directoryStat(int descriptor) {
    final stat = _readStat(descriptor);
    if ((stat.mode & _fileTypeMask) != _directoryMode) {
      throw const ProjectionLayoutPreservingSwapFailure._(
        ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
      );
    }
    return stat;
  }

  _LinuxFileStat _privateDirectoryStat(int descriptor) {
    final stat = _directoryStat(descriptor);
    if (stat.userId != effectiveUserId() ||
        (stat.mode & _authoritativeModeMask) != _privateDirectoryPermissions) {
      throw const ProjectionLayoutPreservingSwapFailure._(
        ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
      );
    }
    return stat;
  }

  _LinuxFileStat _regularSingleLinkStat(
    int descriptor, {
    required int maxBytes,
  }) {
    final stat = _readStat(descriptor);
    if ((stat.mode & _fileTypeMask) != _regularFileMode ||
        stat.linkCount != 1 ||
        stat.size < 0 ||
        stat.size > maxBytes) {
      throw const ProjectionLayoutPreservingSwapFailure._(
        ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
      );
    }
    return stat;
  }

  _LinuxFileStat _authoritativeSourceStat(
    int descriptor, {
    required int maxBytes,
  }) {
    final stat = _regularSingleLinkStat(descriptor, maxBytes: maxBytes);
    if (stat.userId != effectiveUserId()) {
      throw const ProjectionLayoutPreservingSwapFailure._(
        ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
      );
    }
    return stat;
  }

  _LinuxFileStat _privateOwnedRegularSingleLinkStat(
    int descriptor, {
    required int maxBytes,
  }) => _authoritativeSourceStat(descriptor, maxBytes: maxBytes);

  _LinuxFileStat _readStat(int descriptor) {
    final pointer = calloc<_LinuxStat>();
    try {
      if (fstat(descriptor, pointer) != 0) _throwErrno(null, _errno);
      return _linuxFileStat(pointer.ref);
    } finally {
      calloc.free(pointer);
    }
  }

  _LinuxFileStat _readEntryStatAt(int parentFd, String name) {
    final namePointer = name.toNativeUtf8(allocator: calloc);
    final statPointer = calloc<_LinuxStat>();
    try {
      if (fstatAt(parentFd, namePointer, statPointer, _atSymlinkNoFollow) !=
          0) {
        _throwErrno(name, _errno);
      }
      return _linuxFileStat(statPointer.ref);
    } finally {
      calloc.free(statPointer);
      calloc.free(namePointer);
    }
  }

  Uint8List _readStable(
    int descriptor,
    _LinuxFileStat before, {
    required int maxBytes,
  }) {
    final length = before.size;
    final pointer = calloc<ffi.Uint8>(length == 0 ? 1 : length);
    try {
      var offset = 0;
      while (offset < length) {
        final count = pread(
          descriptor,
          (pointer + offset).cast(),
          length - offset,
          offset,
        );
        if (count < 0 && _errno == 4) continue;
        if (count <= 0) _throwErrno(null, count < 0 ? _errno : 5);
        offset += count;
      }
      final after = _regularSingleLinkStat(descriptor, maxBytes: maxBytes);
      if (!_sameStableFile(before, after)) {
        throw const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.ioFailure,
        );
      }
      return Uint8List.fromList(pointer.asTypedList(length));
    } finally {
      calloc.free(pointer);
    }
  }

  void _finishDescriptors(
    List<int> descriptors, {
    required Object? failure,
    required StackTrace? failureStack,
    ProjectionLayoutPreservingSwapFailureCode successfulCloseFailureCode =
        ProjectionLayoutPreservingSwapFailureCode.ioFailure,
  }) {
    int? closeErrno;
    for (final descriptor in descriptors.reversed) {
      if (close(descriptor) != 0) closeErrno ??= _errno;
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
    if (closeErrno != null) {
      throw ProjectionLayoutPreservingSwapFailure._(
        successfulCloseFailureCode,
        diagnosticErrno: closeErrno,
      );
    }
  }

  Object _sanitize(Object error) =>
      error is ProjectionLayoutPreservingSwapFailure ||
          error is ProjectionLayoutSourceConflict
      ? error
      : const ProjectionLayoutPreservingSwapFailure._(
          ProjectionLayoutPreservingSwapFailureCode.ioFailure,
        );

  int get _errno => errnoLocation().value;

  Never _throwErrno(String? path, int errno) {
    throw ProjectionLayoutPreservingSwapFailure._(
      _unsupportedErrnos.contains(errno)
          ? ProjectionLayoutPreservingSwapFailureCode.unsupported
          : _unsafeEntityErrnos.contains(errno)
          ? ProjectionLayoutPreservingSwapFailureCode.unsafeEntity
          : ProjectionLayoutPreservingSwapFailureCode.ioFailure,
      diagnosticPath: path,
      diagnosticErrno: errno,
    );
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameIdentity(_LinuxFileStat left, _LinuxFileStat right) =>
    left.device == right.device &&
    left.inode == right.inode &&
    left.linkCount == right.linkCount &&
    left.mode == right.mode &&
    left.userId == right.userId &&
    left.groupId == right.groupId;

bool _sameInode(_LinuxFileStat left, _LinuxFileStat right) =>
    left.device == right.device &&
    left.inode == right.inode &&
    left.linkCount == right.linkCount;

bool _isRegularSingleLink(_LinuxFileStat stat) =>
    (stat.mode & _LinuxSwapBindings._fileTypeMask) ==
        _LinuxSwapBindings._regularFileMode &&
    stat.linkCount == 1;

bool _sameRawEntryIdentity(_LinuxFileStat left, _LinuxFileStat right) =>
    left.device == right.device &&
    left.inode == right.inode &&
    (left.mode & _LinuxSwapBindings._fileTypeMask) ==
        (right.mode & _LinuxSwapBindings._fileTypeMask);

bool _sameAuthoritativeMetadata(_LinuxFileStat left, _LinuxFileStat right) =>
    (left.mode & _LinuxSwapBindings._authoritativeModeMask) ==
        (right.mode & _LinuxSwapBindings._authoritativeModeMask) &&
    left.userId == right.userId &&
    left.groupId == right.groupId;

Digest _authoritativeMetadataDigest(_LinuxFileStat stat) =>
    Digest.semantic(<String, Object?>{
      'mode': stat.mode & _LinuxSwapBindings._authoritativeModeMask,
      'userId': stat.userId,
      'groupId': stat.groupId,
    });

bool _sameStableFile(_LinuxFileStat left, _LinuxFileStat right) =>
    _sameIdentity(left, right) &&
    left.size == right.size &&
    left.modifiedSeconds == right.modifiedSeconds &&
    left.modifiedNanoseconds == right.modifiedNanoseconds &&
    left.changedSeconds == right.changedSeconds &&
    left.changedNanoseconds == right.changedNanoseconds;

final class _InjectedPostSwapInterruption implements Exception {
  const _InjectedPostSwapInterruption();
}

final class _LinuxFileStat {
  const _LinuxFileStat({
    required this.device,
    required this.inode,
    required this.linkCount,
    required this.mode,
    required this.userId,
    required this.groupId,
    required this.size,
    required this.modifiedSeconds,
    required this.modifiedNanoseconds,
    required this.changedSeconds,
    required this.changedNanoseconds,
  });

  final int device;
  final int inode;
  final int linkCount;
  final int mode;
  final int userId;
  final int groupId;
  final int size;
  final int modifiedSeconds;
  final int modifiedNanoseconds;
  final int changedSeconds;
  final int changedNanoseconds;
}

_LinuxFileStat _linuxFileStat(_LinuxStat stat) => _LinuxFileStat(
  device: stat.device,
  inode: stat.inode,
  linkCount: stat.linkCount,
  mode: stat.mode,
  userId: stat.userId,
  groupId: stat.groupId,
  size: stat.size,
  modifiedSeconds: stat.modified.seconds,
  modifiedNanoseconds: stat.modified.nanoseconds,
  changedSeconds: stat.changed.seconds,
  changedNanoseconds: stat.changed.nanoseconds,
);

final class _LinuxTimespec extends ffi.Struct {
  @ffi.Int64()
  external int seconds;

  @ffi.Int64()
  external int nanoseconds;
}

/// glibc Linux x64 `struct stat` layout. The provider refuses every other ABI.
final class _LinuxStat extends ffi.Struct {
  @ffi.Uint64()
  external int device;

  @ffi.Uint64()
  external int inode;

  @ffi.Uint64()
  external int linkCount;

  @ffi.Uint32()
  external int mode;

  @ffi.Uint32()
  external int userId;

  @ffi.Uint32()
  external int groupId;

  @ffi.Int32()
  external int padding;

  @ffi.Uint64()
  external int deviceType;

  @ffi.Int64()
  external int size;

  @ffi.Int64()
  external int blockSize;

  @ffi.Int64()
  external int blockCount;

  external _LinuxTimespec accessed;
  external _LinuxTimespec modified;
  external _LinuxTimespec changed;

  @ffi.Array.multi(<int>[3])
  external ffi.Array<ffi.Int64> reserved;
}

typedef _OpenNative =
    ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32, ffi.Uint32);
typedef _OpenDart = int Function(ffi.Pointer<Utf8>, int, int);
typedef _OpenAtNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<Utf8>, ffi.Int32, ffi.Uint32);
typedef _OpenAtDart = int Function(int, ffi.Pointer<Utf8>, int, int);
typedef _CloseNative = ffi.Int32 Function(ffi.Int32);
typedef _CloseDart = int Function(int);
typedef _FstatNative = ffi.Int32 Function(ffi.Int32, ffi.Pointer<_LinuxStat>);
typedef _FstatDart = int Function(int, ffi.Pointer<_LinuxStat>);
typedef _FstatAtNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<Utf8>,
      ffi.Pointer<_LinuxStat>,
      ffi.Int32,
    );
typedef _FstatAtDart =
    int Function(int, ffi.Pointer<Utf8>, ffi.Pointer<_LinuxStat>, int);
typedef _PreadNative =
    ffi.IntPtr Function(ffi.Int32, ffi.Pointer<ffi.Void>, ffi.Size, ffi.Int64);
typedef _PreadDart = int Function(int, ffi.Pointer<ffi.Void>, int, int);
typedef _PwriteNative =
    ffi.IntPtr Function(ffi.Int32, ffi.Pointer<ffi.Void>, ffi.Size, ffi.Int64);
typedef _PwriteDart = int Function(int, ffi.Pointer<ffi.Void>, int, int);
typedef _FtruncateNative = ffi.Int32 Function(ffi.Int32, ffi.Int64);
typedef _FtruncateDart = int Function(int, int);
typedef _FchmodNative = ffi.Int32 Function(ffi.Int32, ffi.Uint32);
typedef _FchmodDart = int Function(int, int);
typedef _FchownNative = ffi.Int32 Function(ffi.Int32, ffi.Uint32, ffi.Uint32);
typedef _FchownDart = int Function(int, int, int);
typedef _FsyncNative = ffi.Int32 Function(ffi.Int32);
typedef _FsyncDart = int Function(int);
typedef _MkdirAtNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<Utf8>, ffi.Uint32);
typedef _MkdirAtDart = int Function(int, ffi.Pointer<Utf8>, int);
typedef _RenameAt2Native =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<Utf8>,
      ffi.Int32,
      ffi.Pointer<Utf8>,
      ffi.Uint32,
    );
typedef _RenameAt2Dart =
    int Function(int, ffi.Pointer<Utf8>, int, ffi.Pointer<Utf8>, int);
typedef _GeteuidNative = ffi.Uint32 Function();
typedef _GeteuidDart = int Function();
typedef _ErrnoLocationNative = ffi.Pointer<ffi.Int32> Function();
typedef _ErrnoLocationDart = ffi.Pointer<ffi.Int32> Function();
