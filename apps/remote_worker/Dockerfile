ARG RUNTIME_IMAGE
ARG RUNTIME_KIND
ARG SCRCPY_SERVER_DIGEST
ARG SCRCPY_SERVER_PATH=/opt/scrcpy/scrcpy-server.jar

FROM dart:3.12.2@sha256:5ac89dbcae4327278b257920e2786df0f22c87adc630017266b67cfcceef8348 AS build
ARG RUNTIME_IMAGE
ARG RUNTIME_KIND
ARG SCRCPY_SERVER_DIGEST
WORKDIR /src
COPY . .
RUN printf '%s\n' "$RUNTIME_IMAGE" | \
      grep -Eq '^[^[:space:]@]+@sha256:[0-9a-f]{64}$' && \
    dart pub get --enforce-lockfile && \
    dart compile exe apps/remote_worker/bin/remote_worker.dart -o /out/workspace-remote-worker && \
    dart compile exe apps/remote_session_gateway/bin/remote_session_gateway.dart -o /out/workspace-remote-session-gateway

# RUNTIME_IMAGE must be an immutable OCI digest and contain Chromium. The
# Android variant must additionally contain the pinned SDK, emulator, AVD and
# /dev/kvm-compatible runtime dependencies. No compiler or Flutter SDK is used
# after this stage.
FROM ${RUNTIME_IMAGE} AS runtime
ARG RUNTIME_KIND
ARG SCRCPY_SERVER_DIGEST
ARG SCRCPY_SERVER_PATH=/opt/scrcpy/scrcpy-server.jar
RUN case "$RUNTIME_KIND" in \
      web) test -z "$SCRCPY_SERVER_DIGEST" ;; \
      android) \
        printf '%s\n' "$SCRCPY_SERVER_DIGEST" | grep -Eq '^sha256:[0-9a-f]{64}$' && \
        test -f "$SCRCPY_SERVER_PATH" && \
        test ! -L "$SCRCPY_SERVER_PATH" && \
        expected="$(printf '%s' "$SCRCPY_SERVER_DIGEST" | cut -d: -f2)" && \
        test "$(sha256sum "$SCRCPY_SERVER_PATH" | cut -d' ' -f1)" = "$expected" ;; \
      *) exit 64 ;; \
    esac
COPY --from=build /out/workspace-remote-worker /app/workspace-remote-worker
COPY --from=build /out/workspace-remote-session-gateway /app/workspace-remote-session-gateway
USER 65532:65532
ENTRYPOINT ["/app/workspace-remote-worker"]
