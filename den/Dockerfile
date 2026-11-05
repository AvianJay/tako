# Builds a self-contained server: the AOT executable and the SQLite library
# that package:sqlite3's build hook downloads.
FROM dart:stable AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock* ./
RUN dart pub get
COPY . .
RUN dart run tool/embed_web.dart && dart build cli -o /out

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home /data tako \
 && mkdir /data && chown tako /data
COPY --from=build /out/bundle /app
USER tako
ENV TAKO_DATA=/data TAKO_HOST=0.0.0.0 TAKO_PORT=8787
VOLUME /data
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=3s CMD ["/bin/bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8787 && printf 'GET /healthz HTTP/1.0\\r\\n\\r\\n' >&3 && grep -q ok <&3"]
ENTRYPOINT ["/app/bin/tako_den"]
CMD ["serve"]
