import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/model/workspace_state.dart';

final class StudioWorkspaceController {
  StudioWorkspaceController({
    required this._clientFactory,
    this.reconnectDelay = const Duration(seconds: 2),
  });

  final StudioHostClientFactory _clientFactory;
  final Duration reconnectDelay;
  final StreamController<StudioWorkspaceState> _changes =
      StreamController<StudioWorkspaceState>.broadcast(sync: true);

  StudioWorkspaceState _state = const StudioWorkspaceState.initial();
  StudioHostClient? _client;

  // ignore: cancel_subscriptions
  StreamSubscription<void>? _workspaceSubscription;
  Timer? _reconnectTimer;
  Future<void>? _connectionAttempt;
  bool _closed = false;

  StudioWorkspaceState get state => _state;
  Stream<StudioWorkspaceState> get changes => _changes.stream;
  StudioHostClient? get client => _client;

  Future<void> connect() {
    if (_closed) {
      return Future<void>.error(
        StateError('StudioWorkspaceController is closed'),
      );
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    return _connectionAttempt ??= _connectOnce().whenComplete(() {
      _connectionAttempt = null;
    });
  }

  Future<WorkspaceSnapshot> refreshWorkspace() async {
    if (_closed) {
      throw StateError('StudioWorkspaceController is closed');
    }
    final client = _client;
    if (client == null) throw StateError('Workspace Host is not connected');
    try {
      final content = await _refreshContent(client);
      _acceptContent(client, content);
      return content.snapshot;
    } on Object catch (error) {
      _markStale(error);
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final subscription = _workspaceSubscription;
    _workspaceSubscription = null;
    await subscription?.cancel();
    final client = _client;
    _client = null;
    if (client != null) await _closeClient(client);
    await _changes.close();
  }

  Future<void> _connectOnce() async {
    final previousSubscription = _workspaceSubscription;
    _workspaceSubscription = null;
    await previousSubscription?.cancel();
    final previousClient = _client;
    _client = null;
    if (previousClient != null) await _closeClient(previousClient);
    if (_closed) return;

    final retainedSnapshot = _state.snapshot;
    final retainedExperienceBundle = _state.experienceBundle;
    final retainedScenarioFacets = _state.scenarioFacets;
    final retainedScenarioLab = _state.scenarioLab;
    final retainedMotion = _state.motion;
    final retainedContentIdentity = _state.contentIdentity;
    _publish(
      StudioWorkspaceState(
        snapshot: retainedSnapshot,
        experienceBundle: retainedExperienceBundle,
        scenarioFacets: retainedScenarioFacets,
        scenarioLab: retainedScenarioLab,
        motion: retainedMotion,
        contentIdentity: retainedContentIdentity,
        isConnecting: true,
        connection: retainedSnapshot == null
            ? const WorkspaceConnectionState.unavailable()
            : const WorkspaceConnectionState(
                connected: false,
                isStale: true,
                message: 'Reconectando ao Host',
              ),
      ),
    );

    final client = _clientFactory();
    try {
      final content = await _openContent(client);
      if (_closed) {
        await _closeClient(client);
        return;
      }
      _client = client;
      _publish(
        StudioWorkspaceState(
          snapshot: content.snapshot,
          experienceBundle: content.experienceBundle,
          scenarioFacets: content.scenarioFacets,
          scenarioLab: content.scenarioLab,
          motion: content.motion,
          contentIdentity: content.identity,
          connection: const WorkspaceConnectionState(connected: true),
        ),
      );
      if (client case final StudioHostWorkspaceEvents eventClient) {
        _workspaceSubscription = eventClient.workspaceChanges.listen(
          (_) => unawaited(_acceptHostChange(client)),
          onError: (Object error, StackTrace stackTrace) {
            _markStale(error);
          },
          cancelOnError: true,
        );
      }
    } on Object catch (error) {
      await _closeClient(client);
      if (_closed) return;
      final snapshot = _state.snapshot;
      _publish(
        snapshot == null
            ? StudioWorkspaceState(
                connection: const WorkspaceConnectionState.unavailable(),
                failureMessage: '$error',
              )
            : StudioWorkspaceState(
                snapshot: snapshot,
                experienceBundle: _state.experienceBundle,
                scenarioFacets: _state.scenarioFacets,
                scenarioLab: _state.scenarioLab,
                motion: _state.motion,
                contentIdentity: _state.contentIdentity,
                connection: WorkspaceConnectionState(
                  connected: false,
                  isStale: true,
                  message: '$error',
                ),
              ),
      );
      _scheduleReconnect();
    }
  }

  Future<void> _acceptHostChange(StudioHostClient client) async {
    try {
      final content = await _openContent(client);
      _acceptContent(client, content);
    } on Object catch (error) {
      _markStale(error);
    }
  }

  Future<StudioWorkspaceContent> _openContent(StudioHostClient client) async {
    if (client case final StudioHostContentClient contentClient) {
      return contentClient.openContent();
    }
    throw StateError(
      'Workspace Host client does not implement atomic Experience content',
    );
  }

  Future<StudioWorkspaceContent> _refreshContent(
    StudioHostClient client,
  ) async {
    if (client case final StudioHostContentClient contentClient) {
      return contentClient.refreshContent();
    }
    throw StateError(
      'Workspace Host client does not implement atomic Experience content',
    );
  }

  void _acceptContent(StudioHostClient client, StudioWorkspaceContent content) {
    if (_closed || !identical(_client, client)) return;
    _publish(
      StudioWorkspaceState(
        snapshot: content.snapshot,
        experienceBundle: content.experienceBundle,
        scenarioFacets: content.scenarioFacets,
        scenarioLab: content.scenarioLab,
        motion: content.motion,
        contentIdentity: content.identity,
        connection: const WorkspaceConnectionState(connected: true),
      ),
    );
  }

  void _markStale(Object error) {
    if (_closed || _state.snapshot == null) return;
    _publish(
      StudioWorkspaceState(
        snapshot: _state.snapshot,
        experienceBundle: _state.experienceBundle,
        scenarioFacets: _state.scenarioFacets,
        scenarioLab: _state.scenarioLab,
        motion: _state.motion,
        contentIdentity: _state.contentIdentity,
        connection: WorkspaceConnectionState(
          connected: false,
          isStale: true,
          message: '$error',
        ),
      ),
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer != null) return;
    _reconnectTimer = Timer(reconnectDelay, () {
      _reconnectTimer = null;
      if (!_closed) unawaited(connect());
    });
  }

  Future<void> _closeClient(StudioHostClient client) async {
    try {
      await client.close();
    } on Object {
      // A stale transport must not prevent the next connection attempt.
    }
  }

  void _publish(StudioWorkspaceState next) {
    if (_closed) return;
    _state = next;
    _changes.add(next);
  }
}
