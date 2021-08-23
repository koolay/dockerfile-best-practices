ARG GO_VERSION=1.17

FROM golang:${GO_VERSION}-buster as builder

ARG GOSU_VERSION=1.14
ARG GOPROXY="https://goproxy.cn,direct"

RUN set -ex; \
	if ! command -v gpg > /dev/null; then \
		apt-get update; \
		apt-get install -y --no-install-recommends \
			gnupg \
			dirmngr ca-certificates wget \
		; \
		rm -rf /var/lib/apt/lists/*; \
	fi

RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-$dpkgArch.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true;


WORKDIR /app
COPY go.mod go.sum /app/
RUN go mod download
COPY . /app

RUN set -eux; \
    BUILD_TIME="$(date -u +%Y%m%d.%H%M%S)"; \
    VERSION="$(cat version)"; \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -a -installsuffix cgo \
    -ldflags "-s -w -extldflags '-static' \
    -X main.BuildTime=$BUILD_TIME \
    -X main.Version=$VERSION " \
    -o ./myapp .


FROM debian:buster-slim AS prod

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV TZ "Asia/Shanghai"
ARG TINI_VERSION=v0.19.0
ARG UID=1000
ARG GID=1000

ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /

RUN \
    mkdir /app

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/local/bin/gosu /usr/local/bin/
COPY ./docker-entrypoint.sh /entrypoint.sh

COPY --from=builder /app/myapp /bin/myapp

RUN set -eux \
    gosu nobody true; \
    echo 'Asia/Shanghai' >/etc/timezone; \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    groupadd -r app --gid=${GID} \
    useradd -r -g app --uid=${UID} --shell=/bin/bash app; \
    ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime; \
    echo ${TZ} > /etc/timezone; \
    chmod +x /entrypoint.sh; \
    chown -R app:app /app; \
    chmod +x /tini; \
    chmod +x /bin/myapp;

WORKDIR /app
EXPOSE 8080

ENTRYPOINT ["/tini", "--", "/entrypoint.sh"]
CMD ["myapp"]
