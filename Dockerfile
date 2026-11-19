ARG ALPINE_VERSION=3.24
ARG NGINX_VERSION=1.30.7

FROM alpine:${ALPINE_VERSION} AS build
ARG NGINX_VERSION
ARG OPENSSL_VERSION=4.0.3
ARG PCRE2_VERSION=10.49
ARG ZLIB_VERSION=1.4
ARG LIBMAXMINDDB_VERSION=1.12.2
ARG GEOIP_VERSION=1.6.12
ARG LIBXML2_VERSION=2.15.4
ARG NGX_BROTLI_COMMIT=a71f9312c2deb28875acc7bacfdd5695a111aa53
ARG NGX_GEOIP2_COMMIT=445df24ef3781e488cee3dfe8a1e111997fc1dfe
ARG NGX_SUBS_FILTER_COMMIT=e12e965ac1837ca709709f9a26f572a54d83430e
ARG NGX_DAV_EXT_COMMIT=f5e30888a256136d9c550bf1ada77d6ea78a48af

RUN apk add --no-cache build-base ca-certificates cmake curl git linux-headers patch perl

WORKDIR /build

RUN curl -fSL --retry 3 -o pcre2.tar.gz \
      "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz" \
    && tar -xzf pcre2.tar.gz \
    && curl -fSL --retry 3 -o zlib.tar.gz \
      "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz" \
    && tar -xzf zlib.tar.gz

RUN curl -fSL --retry 3 -o openssl.tar.gz \
      "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
    && tar -xzf openssl.tar.gz

RUN curl -fSL --retry 3 -o geoip.tar.gz \
      "https://github.com/maxmind/geoip-api-c/releases/download/v${GEOIP_VERSION}/GeoIP-${GEOIP_VERSION}.tar.gz" \
    && tar -xzf geoip.tar.gz \
    && cd "GeoIP-${GEOIP_VERSION}" \
    && CFLAGS="-O2 -fPIC" ./configure --enable-static --disable-shared \
    && make -j"$(nproc)" \
    && make install

RUN curl -fSL --retry 3 -o maxminddb.tar.gz \
      "https://github.com/maxmind/libmaxminddb/releases/download/${LIBMAXMINDDB_VERSION}/libmaxminddb-${LIBMAXMINDDB_VERSION}.tar.gz" \
    && tar -xzf maxminddb.tar.gz \
    && cd "libmaxminddb-${LIBMAXMINDDB_VERSION}" \
    && CFLAGS="-O2 -fPIC" ./configure --enable-static --disable-shared \
    && make -j"$(nproc)" \
    && make install

RUN git clone https://github.com/google/ngx_brotli.git \
    && git -C ngx_brotli checkout --detach "${NGX_BROTLI_COMMIT}" \
    && git -C ngx_brotli submodule update --init --depth 1 \
    && cmake -S ngx_brotli/deps/brotli -B ngx_brotli/deps/brotli/out \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    && cmake --build ngx_brotli/deps/brotli/out --parallel "$(nproc)" --target brotlienc

RUN git clone https://github.com/leev/ngx_http_geoip2_module.git \
    && git -C ngx_http_geoip2_module checkout --detach "${NGX_GEOIP2_COMMIT}" \
    && git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git \
    && git -C ngx_http_substitutions_filter_module checkout --detach "${NGX_SUBS_FILTER_COMMIT}"

RUN curl -fSL --retry 3 -o libxml2.tar.xz \
      "https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION%.*}/libxml2-${LIBXML2_VERSION}.tar.xz" \
    && tar -xf libxml2.tar.xz \
    && cd "libxml2-${LIBXML2_VERSION}" \
    && CFLAGS="-O2 -fPIC" ./configure --enable-static --disable-shared --without-python --without-zlib --without-icu \
    && make -j"$(nproc)" \
    && make install

# DAV Ext uses libxml2 directly. Its upstream LIBXSLT hook is optional.
RUN git clone https://github.com/arut/nginx-dav-ext-module.git \
    && git -C nginx-dav-ext-module checkout --detach "${NGX_DAV_EXT_COMMIT}" \
    && sed -i 's/^ngx_module_libs=LIBXSLT$/ngx_module_libs="-lxml2 -lm"/' nginx-dav-ext-module/config

RUN curl -fSL --retry 3 -o nginx.tar.gz "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
    && tar -xzf nginx.tar.gz

WORKDIR /build/nginx-${NGINX_VERSION}

RUN ./configure \
      --prefix=/opt/nginx \
      --http-client-body-temp-path=/opt/nginx/temp/client_body \
      --http-proxy-temp-path=/opt/nginx/temp/proxy \
      --http-fastcgi-temp-path=/opt/nginx/temp/fastcgi \
      --http-uwsgi-temp-path=/opt/nginx/temp/uwsgi \
      --http-scgi-temp-path=/opt/nginx/temp/scgi \
      --with-pcre-jit \
      --with-http_ssl_module \
      --with-http_v2_module \
      --with-http_realip_module \
      --with-http_sub_module \
      --with-http_dav_module \
      --with-http_geoip_module \
      --with-stream \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      --with-stream_geoip_module \
      --with-pcre="/build/pcre2-${PCRE2_VERSION}" \
      --with-zlib="/build/zlib-${ZLIB_VERSION}" \
      --with-openssl="/build/openssl-${OPENSSL_VERSION}" \
      --add-module=/build/ngx_http_substitutions_filter_module \
      --add-module=/build/ngx_brotli \
      --add-module=/build/ngx_http_geoip2_module \
      --add-module=/build/nginx-dav-ext-module \
      --with-cc-opt="-fPIC -I/usr/local/include -I/usr/local/include/libxml2" \
      --with-openssl-opt="no-dso no-async no-tests -fPIC" \
      --with-ld-opt="-static -L/usr/local/lib" \
    && make -j"$(nproc)" \
    && make install \
    && mkdir -p /opt/nginx/temp \
    && strip /opt/nginx/sbin/nginx \
    && ! readelf -l /opt/nginx/sbin/nginx | grep -q INTERP

FROM alpine:${ALPINE_VERSION}
ARG NGINX_VERSION
LABEL org.opencontainers.image.version="${NGINX_VERSION}" \
      org.opencontainers.image.source="https://github.com/wtyone/docker-nginx"

RUN apk add --no-cache ca-certificates

ENV PATH="/opt/nginx/sbin:/opt/nginx/bin:${PATH}"
WORKDIR /opt/nginx

COPY --from=build /opt/nginx /opt/nginx
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Keep defaults outside the bind mounts so empty host directories can be seeded.
RUN mkdir -p /usr/local/share/nginx-defaults \
    && cp -a conf html /usr/local/share/nginx-defaults/ \
    && nginx -V \
    && nginx -t \
    && rm -rf /opt/nginx/temp/* \
    && chmod 1777 /opt/nginx/temp \
    && apk add --no-cache --virtual .setcap libcap-setcap \
    && setcap cap_net_bind_service=+ep /opt/nginx/sbin/nginx \
    && apk del .setcap

STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
