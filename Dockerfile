FROM debian:bookworm-slim AS extractor

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        innoextract \
    && rm -rf /var/lib/apt/lists/*

COPY installer/EcmSpy_Mono_2.0-Setup.exe /tmp/setup.exe

RUN innoextract -e -m --output-dir /extracted /tmp/setup.exe

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV HOME=/home/ecmspy

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        mono-complete \
        gtk-sharp2 \
        libgtk2.0-cil \
        libglade2.0-cil \
        xvfb \
        x11vnc \
        fluxbox \
        novnc \
        websockify \
        socat \
        procps \
    && rm -rf /var/lib/apt/lists/*

RUN useradd \
        --create-home \
        --home-dir /home/ecmspy \
        --shell /bin/bash \
        ecmspy \
    && mkdir -p \
        /home/ecmspy/ecmspy/applog \
        /home/ecmspy/data \
    && chown -R ecmspy:ecmspy /home/ecmspy

COPY --from=extractor --chown=ecmspy:ecmspy /extracted/app/ /home/ecmspy/ecmspy/

COPY --chown=ecmspy:ecmspy start-ecmspy.sh /usr/local/bin/start-ecmspy

RUN chmod 755 /usr/local/bin/start-ecmspy

USER ecmspy

WORKDIR /home/ecmspy/ecmspy

EXPOSE 6080

CMD ["/usr/local/bin/start-ecmspy"]