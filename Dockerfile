FROM debian:bookworm-slim AS extractor

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        innoextract \
    && rm -rf /var/lib/apt/lists/*

COPY installer/EcmSpy_Mono_2.0-Setup.exe /tmp/setup.exe

RUN innoextract -e -m --output-dir /extracted /tmp/setup.exe \
    && sed -i 's/xs:sring/xs:string/' /extracted/app/files.xml

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV HOME=/home/ecmspy

# Debian's own mono-complete (6.8.0.105) predates a Mono fix for Linux
# kernels >=5.13, which return ENOTTY (not EINVAL) when a program tries to
# set DTR/RTS on a pseudo-terminal; unpatched Mono treats that as fatal,
# crashing EcmSpy's SerialPort.Open() against the bridged PTY. The official
# Mono project apt repo ships 6.12.0.200, which includes the fix
# (https://github.com/mono/mono/pull/21204). Installing the mono-complete
# metapackage as-is from this repo fails outright (its monodoc-http /
# mono-xsp4 postinst scripts error out in a minimal container); installing
# specific packages instead resolves a working set (gtk-sharp2 still pulls
# in mono-devel/monodoc/mono-xsp4 transitively, but via an install order
# that configures cleanly here).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gnupg \
        ca-certificates \
    && gpg --homedir /tmp --no-default-keyring \
        --keyring gnupg-ring:/usr/share/keyrings/mono-official-archive-keyring.gpg \
        --keyserver hkp://keyserver.ubuntu.com:80 \
        --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
    && chmod 644 /usr/share/keyrings/mono-official-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/mono-official-archive-keyring.gpg] https://download.mono-project.com/repo/debian stable-buster main" \
        > /etc/apt/sources.list.d/mono-official-stable.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        mono-runtime \
        libmono-system-data4.0-cil \
        libmono-system-xml4.0-cil \
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
        gosu \
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
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 755 /usr/local/bin/start-ecmspy /usr/local/bin/entrypoint.sh

WORKDIR /home/ecmspy/ecmspy

EXPOSE 6080

# Starts as root (see entrypoint.sh) to set up a /dev symlink, then drops
# to the ecmspy user via gosu for the rest of the startup sequence.
CMD ["/usr/local/bin/entrypoint.sh"]