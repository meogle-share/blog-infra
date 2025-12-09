#!/bin/bash
set -e

DOMAIN="www.meogle.co.kr"
EMAIL="${CERTBOT_EMAIL:-jmsavemail@gmail.com}"
COMPOSE_CMD="docker compose -p meogle -f docker-compose.yml -f docker-compose.prod.yml"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

usage() {
    echo "Usage: $0 {init|init-staging|renew}"
    echo ""
    echo "Commands:"
    echo "  init         - 초기 인증서 발급"
    echo "  init-staging - 테스트용 인증서 발급 (rate limit 없음)"
    echo "  renew        - 인증서 갱신 (무중단)"
    exit 1
}

create_dummy_cert() {
    echo "==> Creating dummy certificate for nginx startup..."
    $COMPOSE_CMD run --rm --entrypoint sh certbot -c "\
        mkdir -p $CERT_PATH && \
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
            -keyout $CERT_PATH/privkey.pem \
            -out $CERT_PATH/fullchain.pem \
            -subj '/CN=$DOMAIN'"
}

remove_dummy_cert() {
    echo "==> Removing dummy certificate..."
    $COMPOSE_CMD run --rm --entrypoint sh certbot -c "\
        rm -rf /etc/letsencrypt/live/$DOMAIN && \
        rm -rf /etc/letsencrypt/archive/$DOMAIN && \
        rm -f /etc/letsencrypt/renewal/$DOMAIN.conf"
}

init() {
    local staging_flag=""
    if [ "${1:-}" = "staging" ]; then
        staging_flag="--staging"
        echo "==> [STAGING] 테스트 모드로 실행합니다."
    fi

    # 1. 더미 인증서 생성 (nginx 시작용)
    create_dummy_cert

    # 2. nginx 시작 (더미 인증서로 SSL 작동)
    echo "==> Starting nginx with dummy certificate..."
    $COMPOSE_CMD up -d --force-recreate web
    sleep 5

    # 3. 더미 인증서 삭제 (certbot이 깨끗하게 발급할 수 있도록)
    remove_dummy_cert

    # 4. 실제 인증서 발급
    echo "==> Requesting certificate for $DOMAIN..."
    $COMPOSE_CMD run --rm certbot certonly \
        --webroot \
        -w /var/www/certbot \
        --agree-tos \
        --no-eff-email \
        --email "$EMAIL" \
        $staging_flag \
        -d "$DOMAIN"

    # 5. nginx reload로 실제 인증서 적용
    echo "==> Reloading nginx with real certificate..."
    docker exec meogle.nginx nginx -s reload

    echo "==> Done! Certificate issued successfully."
}

renew() {
    echo "==> Renewing certificates..."
    $COMPOSE_CMD run --rm certbot renew

    echo "==> Reloading nginx..."
    docker exec meogle.nginx nginx -s reload

    echo "==> Done! Certificates renewed."
}

case "${1:-}" in
    init)
        init
        ;;
    init-staging)
        init staging
        ;;
    renew)
        renew
        ;;
    *)
        usage
        ;;
esac