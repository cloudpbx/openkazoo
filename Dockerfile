# OpenKazoo dev/test image: CI toolchain (OTP 27, rebar3 3.27.0) + emacs
# (formatter) + Go (martini libsecsipid) + fax/document conversion tools.
# Toolchain only; the source tree is bind-mounted at runtime.
FROM erlang:27

ARG REBAR3_VERSION=3.27.0
ARG GO_VERSION=1.26.0
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        emacs-nox git make pkg-config curl netcat-traditional \
        ghostscript libreoffice fonts-dejavu libtiff-tools \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fSL -o /usr/local/bin/rebar3 \
        "https://github.com/erlang/rebar3/releases/download/${REBAR3_VERSION}/rebar3" \
    && chmod +x /usr/local/bin/rebar3

RUN curl -fSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

WORKDIR /src
CMD ["sleep", "infinity"]
