#!/bin/bash
set -e
set -o pipefail

################################################################################
# NGINX Custom Build for High-Performance Laravel Hosting (com NJS dinâmico)
################################################################################

NGINX_VERSION="1.28.0"
OPENSSL_QUIC_BRANCH="openssl-3.3.1+quic"
NJS_VERSION=$(curl -s http://nginx.org/en/download.html | grep -oP 'njs-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.gz)' | head -n1)
if [[ -z "$NJS_VERSION" ]]; then
  echo "⚠️ Falha ao detectar versão mais recente do NJS. Usando versão fixa 0.8.2"
  NJS_VERSION="0.8.2"
fi

echo "📦 Usando NJS versão: $NJS_VERSION"
PAGESPEED_VERSION="1.13.35.2-stable"
PSOL_VERSION="1.13.35.2-x64-linux"
BUILD_DIR="/tmp/nginx-build"

export DEBIAN_FRONTEND=noninteractive

echo "🚀 Iniciando build NGINX ${NGINX_VERSION} com NJS dinâmico …"

apt update && apt install -y --no-install-recommends \
  build-essential git wget curl unzip libtool automake autoconf cmake \
  zlib1g-dev libpcre3-dev libmaxminddb-dev pkg-config libssl-dev libgd-dev \
  ca-certificates uuid-dev

# ─────────────── ngtcp2 stack ───────────────
if ! ldconfig -p | grep -q libngtcp2; then
  echo "⚙️ Compilando ngtcp2 stack…"
  cd /tmp
  rm -rf sfparse nghttp3 ngtcp2

  git clone https://github.com/ngtcp2/sfparse.git
  cd sfparse && autoreconf -fi && ./configure --prefix=/usr/local && make -j$(nproc) && make install && ldconfig
  cd ..

  git clone https://github.com/ngtcp2/nghttp3.git
  cd nghttp3 && autoreconf -fi && ./configure --prefix=/usr/local && make -j$(nproc) && make install && ldconfig
  cd ..

  git clone https://github.com/ngtcp2/ngtcp2.git
  cd ngtcp2 && autoreconf -fi && ./configure --prefix=/usr/local --with-libnghttp3=/usr/local && make -j$(nproc) && make install && ldconfig
  cd ..
fi

# ─────────────── Setup inicial ───────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

mkdir -p /etc/nginx/{conf.d,sites-available,sites-enabled,geoip2,modules}
mkdir -p /var/log/nginx /var/cache/nginx /var/run

groupadd --system www-data 2>/dev/null || true
useradd  --system --no-create-home --shell /usr/sbin/nologin \
        -g www-data www-data 2>/dev/null || true
chown -R www-data:www-data /var/log/nginx /var/cache/nginx

retry() {
  local n=0
  until "$@"; do
    n=$((n+1)); [[ $n -lt 5 ]] || exit 1
    echo "🔄 Retry $n…"
    sleep $((2 ** n))
  done
}

retry wget -q http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
retry wget -q http://nginx.org/download/njs-${NJS_VERSION}.tar.gz

retry git clone --recursive https://github.com/google/ngx_brotli.git
retry git clone https://github.com/openresty/headers-more-nginx-module.git
retry git clone https://github.com/leev/ngx_http_geoip2_module.git
retry git clone https://github.com/apache/incubator-pagespeed-ngx.git pagespeed
pushd pagespeed >/dev/null
retry git checkout -q v${PAGESPEED_VERSION}
retry wget -q https://dl.google.com/dl/page-speed/psol/${PSOL_VERSION}.tar.gz -O ${PSOL_VERSION}.tar.gz
retry tar -xzf ${PSOL_VERSION}.tar.gz
popd >/dev/null

retry git clone --depth=1 -b ${OPENSSL_QUIC_BRANCH} https://github.com/quictls/openssl.git quic-openssl

tar -xzf nginx-${NGINX_VERSION}.tar.gz
tar -xzf njs-${NJS_VERSION}.tar.gz

pushd ngx_brotli/deps/brotli >/dev/null
mkdir -p out && cd out
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
         -DCMAKE_INSTALL_PREFIX=./installed \
         -DCMAKE_C_FLAGS="-Ofast -march=native -mtune=native"
make brotlienc -j"$(nproc)"
strip --strip-unneeded brotli*
popd >/dev/null

cd nginx-${NGINX_VERSION}

export CFLAGS="-O3 -march=native -mtune=native -flto -fdata-sections \
               -ffunction-sections -fstack-protector-strong -D_FORTIFY_SOURCE=2"
export LDFLAGS="-Wl,--as-needed -Wl,--gc-sections -Wl,-z,relro -Wl,-z,now"

./configure \
  --prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/var/run/nginx.pid \
  --lock-path=/var/lock/nginx.lock \
  --user=www-data --group=www-data \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-http_dav_module \
  --with-http_realip_module \
  --with-http_stub_status_module \
  --with-http_gzip_static_module \
  --with-http_sub_module \
  --with-http_mp4_module \
  --with-http_slice_module \
  --with-http_auth_request_module \
  --with-threads --with-file-aio \
  --with-stream --with-stream_ssl_module \
  --with-compat \
  --with-openssl=../quic-openssl \
  --with-openssl-opt="enable-ktls" \
  --add-module=../ngx_brotli \
  --add-module=../headers-more-nginx-module \
  --add-module=../ngx_http_geoip2_module \
  --add-module=../pagespeed \
  --add-dynamic-module=../njs-${NJS_VERSION}/nginx

make -j"$(nproc)"
make install

if [[ ! -f /usr/sbin/nginx ]]; then
  echo "❌ nginx não foi instalado corretamente."
  find / -name nginx -type f 2>/dev/null
  exit 1
fi

cp objs/ngx_http_js_module.so /etc/nginx/modules/

if ! grep -q "load_module modules/ngx_http_js_module.so;" /etc/nginx/nginx.conf 2>/dev/null; then
  sed -i '1iload_module modules/ngx_http_js_module.so;' /etc/nginx/nginx.conf
fi

mkdir -p /etc/nginx/snippets
cp -r ./nginx/snippets/* /etc/nginx/snippets/ 2>/dev/null || true

echo "✅ NGINX compilado/instalado com NJS dinâmico."

cd /etc/nginx/geoip2
retry wget -q https://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.tar.gz -O GeoLite2-Country.tar.gz

tar -xzf GeoLite2-Country.tar.gz --strip-components=1 --wildcards */GeoLite2-Country.mmdb
rm GeoLite2-Country.tar.gz

if [[ -n "$NGINX_CONF_URL" ]]; then
  echo "🌐 Usando nginx.conf de $NGINX_CONF_URL"
  curl -fsSL "$NGINX_CONF_URL" -o /etc/nginx/nginx.conf
else
  echo "📦 Usando nginx.conf local de ./nginx/conf.d/nginx.conf"
  cp ./nginx/conf.d/nginx.conf /etc/nginx/nginx.conf 2>/dev/null || true
fi

echo "🧪 Testando configuração do NGINX..."
/usr/sbin/nginx -t || { echo "❌ Erro na configuração do NGINX"; exit 1; }

# Limpeza segura apenas após sucesso
apt purge -y build-essential git wget curl libtool automake autoconf cmake \
              zlib1g-dev libpcre3-dev libmaxminddb-dev pkg-config libssl-dev libgd-dev uuid-dev || true
apt autoremove -y --purge && apt clean
rm -rf /var/lib/apt/lists/* "$BUILD_DIR"

# NGINX é iniciado em outro ponto (ex: systemd, supervisord ou manualmente)
echo "✅ Script finalizado com sucesso. NGINX instalado."
/usr/sbin/nginx -v
