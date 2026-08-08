FROM dart:3.12.2@sha256:5ac89dbcae4327278b257920e2786df0f22c87adc630017266b67cfcceef8348 AS build
WORKDIR /src
COPY . .
RUN dart pub get --enforce-lockfile && \
    dart compile exe apps/hosted_control_plane/bin/hosted_control_plane.dart -o /out/control-plane-control-plane && \
    dart compile exe apps/hosted_control_plane/bin/migrate.dart -o /out/control-plane-migrate

FROM gcr.io/distroless/base-debian12:nonroot@sha256:63f52bd27b6aa6555f5d56500b70d7bb0afe51c654905be88a2c1cf967a77b1a
COPY --from=build /out/control-plane-control-plane /app/control-plane-control-plane
COPY --from=build /out/control-plane-migrate /app/control-plane-migrate
COPY --from=build /src/apps/hosted_control_plane/migrations /app/migrations
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/control-plane-control-plane"]
