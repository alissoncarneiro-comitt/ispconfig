#!/bin/bash
set -e
set -o pipefail

NGINX_VERSION="1.28.0"
OPENSSL_VERSION="openssl-3.3.1"
BUILD_DIR="/tmp/nginx-build"

export DEBIAN_FRONTEND=noninteractive

echo "Iniciando build NGINX ${NGINX_VERSION} com NJS dinâmico (versão robusta)..."

# Detectar número de cores disponíveis com limite máximo
NPROC=$(nproc)
MAKE_JOBS=$((NPROC > 6 ? 6 : NPROC))
echo "🔧 Usando ${MAKE_JOBS} jobs paralelos (de ${NPROC} cores disponíveis)"

# Instalar dependências
apt update && apt install -y --no-install-recommends \
  build-essential git wget curl unzip libtool automake autoconf cmake \
  zlib1g-dev libpcre3-dev libmaxminddb-dev pkg-config libssl-dev libgd-dev \
  ca-certificates uuid-dev libxml2-dev libxslt1-dev

if ! ldconfig -p | grep -q libngtcp2; then
  echo "Compilando ngtcp2 stack..."
  cd /tmp
  rm -rf sfparse nghttp3 ngtcp2

  # Flags otimizadas mas seguras
  export CFLAGS_SAFE="-O2 -pipe"
  export LDFLAGS_SAFE="-Wl,--as-needed"

  git clone --depth=1 https://github.com/ngtcp2/sfparse.git
  cd sfparse && autoreconf -fi && CFLAGS="$CFLAGS_SAFE" LDFLAGS="$LDFLAGS_SAFE" ./configure --prefix=/usr/local && make -j${MAKE_JOBS} && make install && sudo ldconfig
  cd ..

  git clone --depth=1 https://github.com/ngtcp2/nghttp3.git
  cd nghttp3 && autoreconf -fi && CFLAGS="$CFLAGS_SAFE" LDFLAGS="$LDFLAGS_SAFE" ./configure --prefix=/usr/local && make -j${MAKE_JOBS} && make install && sudo ldconfig
  cd ..

  git clone --depth=1 https://github.com/ngtcp2/ngtcp2.git
  cd ngtcp2 && autoreconf -fi && CFLAGS="$CFLAGS_SAFE" LDFLAGS="$LDFLAGS_SAFE" ./configure --prefix=/usr/local --with-libnghttp3=/usr/local && make -j${MAKE_JOBS} && make install && sudo ldconfig
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
    n=$((n+1)); [[ $n -lt 3 ]] || exit 1
    echo "🔄 Retry $n..."
    sleep $n
  done
}

# Downloads paralelos
echo "📥 Baixando fontes..."
retry wget -q http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz &
retry git clone --depth=1 https://github.com/nginx/njs.git njs &
retry git clone --depth=1 --recursive https://github.com/google/ngx_brotli.git &
retry git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git &
retry git clone --depth=1 https://github.com/leev/ngx_http_geoip2_module.git &
retry git clone --depth=1 -b ${OPENSSL_VERSION} https://github.com/openssl/openssl.git quic-openssl &

wait

tar -xzf nginx-${NGINX_VERSION}.tar.gz

# Otimizar Brotli
pushd ngx_brotli/deps/brotli >/dev/null
mkdir -p out && cd out
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
         -DCMAKE_INSTALL_PREFIX=./installed \
         -DCMAKE_C_FLAGS="-O2 -pipe"
make brotli brotlienc -j${MAKE_JOBS}
popd >/dev/null

cd nginx-${NGINX_VERSION}

# Flags de compilação seguras e otimizadas
export CFLAGS="-O2 -pipe -fstack-protector-strong"
export LDFLAGS="-Wl,--as-needed"

echo "🔧 Configurando NGINX..."
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

echo "🏗️ Compilando NGINX (esta é a parte mais demorada)..."
echo "⏱️ Compilação do OpenSSL pode demorar 10-15 minutos, aguarde..."

# Usar menos jobs para OpenSSL (mais estável)
make -j$((MAKE_JOBS > 4 ? 4 : MAKE_JOBS))
make install

cp objs/ngx_http_js_module.so /etc/nginx/modules/

if ! grep -q "load_module modules/ngx_http_js_module.so;" /etc/nginx/nginx.conf 2>/dev/null; then
  sed -i '1iload_module modules/ngx_http_js_module.so;' /etc/nginx/nginx.conf
fi

mkdir -p /etc/nginx/snippets
cp -r ./nginx/snippets/* /etc/nginx/snippets/ 2>/dev/null || true

echo "✅ NGINX compilado/instalado com NJS dinâmico."

# Download do GeoIP
echo "📍 Baixando bases GeoIP..."
mkdir -p /etc/nginx/geoip2
cd /etc/nginx/geoip2
rm -f GeoIP2-Country.mmdb*

GEOIP_URLS=(
    "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb.gz" 
    "https://dl.miyuru.lk/geoip/maxmind/country/maxmind.dat.gz" 
)

for url in "${GEOIP_URLS[@]}"; do
    if timeout 60 wget -q --timeout=30 --tries=2 "$url" -O GeoIP2-Country.mmdb.gz; then
        gzip -df GeoIP2-Country.mmdb.gz > /dev/null 2>&1 && break
    fi
done

# Configuração
if [[ -n "${NGINX_CONF_URL:-}" ]]; then
  echo "🌐 Usando nginx.conf de $NGINX_CONF_URL"
  curl -fsSL "$NGINX_CONF_URL" -o /etc/nginx/nginx.conf
else
  echo "📦 Usando nginx.conf local"
  cp ./nginx/conf.d/nginx.conf /etc/nginx/nginx.conf 2>/dev/null || true
fi

echo "🔍 Verificando dependências runtime do NGINX..."
# Descobrir quais bibliotecas o NGINX precisa
NGINX_DEPS=$(ldd /usr/sbin/nginx 2>/dev/null | awk '/=>/ {print $1}' | sort -u)
echo "Dependências detectadas: $NGINX_DEPS"

# Verificar dependências essenciais
REQUIRED_LIBS=(
  "libpcre.so.3"
  "libssl.so.3" 
  "libcrypto.so.3"
  "libz.so.1"
  "libmaxminddb.so.0"
)

echo "🔧 Instalando bibliotecas runtime necessárias..."
for lib in "${REQUIRED_LIBS[@]}"; do
  if ! ldconfig -p | grep -q "$lib"; then
    echo "Instalando biblioteca: $lib"
    case "$lib" in
      "libpcre.so.3") apt-get install -y --no-install-recommends libpcre3 ;;
      "libssl.so.3"|"libcrypto.so.3") apt-get install -y --no-install-recommends libssl3 ;;
      "libz.so.1") apt-get install -y --no-install-recommends zlib1g ;;
      "libmaxminddb.so.0") apt-get install -y --no-install-recommends libmaxminddb0 ;;
    esac
  fi
done

# Marcar bibliotecas runtime como instaladas manualmente
echo "📌 Marcando bibliotecas essenciais como manuais..."
apt-mark manual \
  libpcre3 \
  libssl3 \
  libcrypto3 \
  zlib1g \
  libmaxminddb0 \
  libgd3 \
  libxml2 \
  libxslt1.1 \
  ca-certificates \
  2>/dev/null || true

echo "🧪 Testando configuração do NGINX antes da limpeza..."
nginx -t

echo "🧹 Limpando ambiente de build (mantendo bibliotecas runtime)..."

# Remover apenas ferramentas de desenvolvimento
apt-get purge -y \
  build-essential \
  git \
  wget \
  curl \
  libtool \
  automake \
  autoconf \
  cmake \
  pkg-config \
  unzip

# Remover headers de desenvolvimento mas manter bibliotecas runtime
apt-get purge -y \
  zlib1g-dev \
  libpcre3-dev \
  libssl-dev \
  libgd-dev \
  uuid-dev \
  libxml2-dev \
  libxslt1-dev \
  libmaxminddb-dev

# Limpeza cuidadosa
apt-get autoremove -y --purge
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/nginx-build

echo "🔍 Verificação final das dependências..."
if ldd /usr/sbin/nginx | grep -q "not found"; then
  echo "❌ ERRO: Algumas dependências estão faltando:"
  ldd /usr/sbin/nginx | grep "not found"
  exit 1
fi

echo "✅ Todas as dependências estão OK!"

echo "🧪 Teste final de configuração do NGINX..."
nginx -t

echo "🚀 Subindo NGINX (daemon off)..."
exec nginx -g 'daemon off;'