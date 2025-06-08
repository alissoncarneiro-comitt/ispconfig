#!/bin/bash
set -e
set -o pipefail

NGINX_VERSION="1.28.0"
OPENSSL_VERSION="openssl-3.3.1"
BUILD_DIR="/tmp/nginx-build"

export DEBIAN_FRONTEND=noninteractive

echo "Iniciando build NGINX ${NGINX_VERSION} com NJS dinâmico …"


apt update && apt install -y --no-install-recommends \
  build-essential git wget curl unzip libtool automake autoconf cmake \
  zlib1g-dev libpcre3-dev libmaxminddb-dev pkg-config libssl-dev libgd-dev \
  ca-certificates uuid-dev libxml2-dev libxslt1-dev

if ! ldconfig -p | grep -q libngtcp2; then
  echo "Compilando ngtcp2 stack…"
  cd /tmp
  rm -rf sfparse nghttp3 ngtcp2

  git clone https://github.com/ngtcp2/sfparse.git
  cd sfparse && autoreconf -fi && ./configure --prefix=/usr/local && make -j$(nproc) && make install && sudo ldconfig
  cd ..

  git clone https://github.com/ngtcp2/nghttp3.git
  cd nghttp3 && autoreconf -fi && ./configure --prefix=/usr/local && make -j$(nproc) && make install && sudo ldconfig
  cd ..

  git clone https://github.com/ngtcp2/ngtcp2.git
  cd ngtcp2 && autoreconf -fi && ./configure --prefix=/usr/local --with-libnghttp3=/usr/local && make -j$(nproc) && make install && sudo ldconfig
  cd ..
fi

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
retry git clone https://github.com/nginx/njs.git njs

retry git clone --recursive https://github.com/google/ngx_brotli.git
retry git clone https://github.com/openresty/headers-more-nginx-module.git
retry git clone https://github.com/leev/ngx_http_geoip2_module.git

retry git clone --depth=1 -b ${OPENSSL_VERSION} https://github.com/openssl/openssl.git quic-openssl

tar -xzf nginx-${NGINX_VERSION}.tar.gz

pushd ngx_brotli/deps/brotli >/dev/null
mkdir -p out && cd out
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
         -DCMAKE_INSTALL_PREFIX=./installed \
         -DCMAKE_C_FLAGS="-Ofast -march=native -mtune=native"
make brotli brotlienc -j"$(nproc)"
strip --strip-unneeded brotli
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
  --with-openssl-opt="enable-tls1_3 enable-ktls enable-quic" \
  --add-module=../ngx_brotli \
  --add-module=../headers-more-nginx-module \
  --add-module=../ngx_http_geoip2_module \
  --add-dynamic-module=../njs/nginx 


make -j"$(nproc)"
make install

cp objs/ngx_http_js_module.so /etc/nginx/modules/

if ! grep -q "load_module modules/ngx_http_js_module.so;" /etc/nginx/nginx.conf 2>/dev/null; then
  sed -i '1iload_module modules/ngx_http_js_module.so;' /etc/nginx/nginx.conf
fi

mkdir -p /etc/nginx/snippets
cp -r ./nginx/snippets/* /etc/nginx/snippets/ 2>/dev/null || true

echo "NGINX compilado/instalado com NJS dinâmico."


mkdir -p /etc/nginx/geoip2
cd /etc/nginx/geoip2
retry wget -q "https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz" -O GeoIP2-Country.mmdb.gz
gzip -d GeoIP2-Country.mmdb.gz  

if [ ! -f /etc/nginx/geoip2/GeoIP2-Country.mmdb ]; then
  echo "Falha no download do GeoIP2" >&2
  exit 1
fi

if [[ -n "${NGINX_CONF_URL:-}" ]]; then
  echo "🌐 Usando nginx.conf de $NGINX_CONF_URL"
  curl -fsSL "$NGINX_CONF_URL" -o /etc/nginx/nginx.conf
else
  echo "📦 Usando nginx.conf local de ./nginx/conf.d/nginx.conf"
  cp ./nginx/conf.d/nginx.conf /etc/nginx/nginx.conf 2>/dev/null || true
fi



echo "Limpando ambiente de build…"
apt purge -y build-essential git wget curl libtool automake autoconf cmake \
              zlib1g-dev libpcre3-dev libmaxminddb-dev pkg-config libssl-dev libgd-dev uuid-dev || true
apt autoremove -y --purge && apt clean
rm -rf /var/lib/apt/lists/* "$BUILD_DIR"

echo "Testando configuração do NGINX..."
nginx -t

echo "🚀 Subindo NGINX (daemon off)…"
exec nginx -g 'daemon off;'
