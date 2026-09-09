FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TEXLIVE_REPO=https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2025/tlnet-final
ENV TEXLIVE_DIR=/opt/texlive/2025
ENV PATH=/opt/texlive/2025/bin/x86_64-linux:${PATH}
ENV LUALATEX_PATH=/opt/texlive/2025/bin/x86_64-linux/lualatex

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    fontconfig \
    git \
    pandoc \
    perl \
    poppler-utils \
    python3-pil \
    ruby \
    tar \
    xz-utils \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/texlive-installer

COPY docker/texlive-2025.profile /tmp/texlive-installer/texlive-2025.profile

RUN curl -L --fail -o install-tl-2025.tar.gz ${TEXLIVE_REPO}/install-tl-unx.tar.gz \
 && mkdir install-tl \
 && tar -xzf install-tl-2025.tar.gz -C install-tl --strip-components=1 \
 && install-tl/install-tl --profile /tmp/texlive-installer/texlive-2025.profile --repository ${TEXLIVE_REPO} \
 && ${TEXLIVE_DIR}/bin/x86_64-linux/tlmgr install jlreq luatexja titlesec haranoaji lualatex-math selnolig lua-ul luacolor \
 && rm -rf /tmp/texlive-installer

WORKDIR /workspace

COPY . /workspace

CMD ["bash"]
