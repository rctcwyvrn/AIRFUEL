# Airfuel dedicated lobby server (matchmaker + relay — never simulates).
# Build from the REPO ROOT:  docker build -f docker/Dockerfile -t airfuel-server .
# Run:                       docker run --rm -p 27555:27555/udp airfuel-server
#
# GODOT_VERSION must match the version the project is developed with
# (`godot4 --version` in the nix shell) — a mismatched server can desync
# scene/rpc expectations.

FROM debian:bookworm-slim

ARG GODOT_VERSION=4.6.1

ADD https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip /tmp/godot.zip

# Godot's linux binary dynamically links these even when run --headless.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		unzip ca-certificates libfontconfig1 libx11-6 libxcursor1 \
		libxinerama1 libxrandr2 libxi6 libgl1 \
	&& rm -rf /var/lib/apt/lists/* \
	&& unzip -q /tmp/godot.zip -d /tmp \
	&& mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
	&& rm /tmp/godot.zip \
	&& useradd -m airfuel

COPY game/ /app/game/

# Pre-import at build time so container boot is instant, then hand the tree
# to the runtime user (Godot still writes logs/shader caches under HOME).
RUN godot --headless --path /app/game --import; chown -R airfuel /app/game

USER airfuel
ENV HOME=/home/airfuel

EXPOSE 27555/udp
CMD ["godot", "--headless", "--path", "/app/game", "--", "--dedicated"]
