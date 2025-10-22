#!/usr/bin/env bash
#
# install.sh - Automated deployment script for Russian placeholder site
# Configures Nginx + Certbot + SNI site on 127.0.0.1:8443 with Proxy Protocol
#
# Usage:
#   Interactive:   bash install.sh
#   Non-interactive: bash install.sh --domain example.com --email admin@example.com
#   Dry run:       bash install.sh --domain example.com --dry-run
#   Help:          bash install.sh --help
#

set -euo pipefail

# ============================================================================
# Constants and Configuration
# ============================================================================

SCRIPT_VERSION="1.0.0"
REQUIRED_TOOLS="nginx certbot curl tar rsync"
NGINX_BACKUP_BASE="/etc/nginx/backup"
SITE_ROOT="/var/www/html/site"
SNI_CONFIG="/etc/nginx/sites-available/sni.conf"
GITHUB_REPO="alche-my/temp-vpn-site"
GITHUB_BRANCH="main"

# ============================================================================
# Global Variables
# ============================================================================

DOMAIN=""
EMAIL=""
DRY_RUN=false
LOG_FILE=""
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# ============================================================================
# Helper Functions
# ============================================================================

# Print help message
show_help() {
    cat <<EOF
Установка SNI-сайта для Reality/VLESS

Использование:
  Интерактивный режим:
    bash -c "\$(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh)"

  Неинтерактивный режим:
    curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh | bash -s -- \\
      --domain video.mashina.online --email admin@video.mashina.online

Опции:
  --domain <domain>   Целевой домен (например, video.mashina.online)
  --email <email>     Email для уведомлений Let's Encrypt (по умолчанию: admin@<domain>)
  --dry-run           Показать шаги без внесения изменений
  --help              Показать это сообщение

Примеры:
  # Интерактивный режим
  bash install.sh

  # С явными параметрами
  bash install.sh --domain example.com --email admin@example.com

  # Тестовый прогон
  bash install.sh --domain example.com --dry-run

Версия: ${SCRIPT_VERSION}
EOF
    exit 0
}

# Print colored output
print_step() {
    echo ""
    echo "=========================================="
    echo "▶ $1"
    echo "=========================================="
}

print_success() {
    echo "✓ $1"
}

print_error() {
    echo "✗ ОШИБКА: $1" >&2
}

print_warning() {
    echo "⚠ ПРЕДУПРЕЖДЕНИЕ: $1"
}

print_info() {
    echo "ℹ $1"
}

# Execute command with dry-run support
execute() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $*"
        return 0
    else
        "$@"
    fi
}

# Check if running as root
check_root() {
    if [ "$DRY_RUN" = true ]; then
        print_info "Режим dry-run: проверка root пропущена"
        return 0
    fi

    if [ "$EUID" -ne 0 ]; then
        print_error "Этот скрипт должен запускаться с правами root."
        echo "Пожалуйста, выполните:"
        echo "  sudo bash $0 $*"
        exit 1
    fi
}

# Initialize log file
init_log() {
    if [ "$DRY_RUN" = true ]; then
        LOG_FILE="/tmp/vpn-placeholder-install-dryrun-${TIMESTAMP}.log"
        print_info "Режим сухого прогона. Лог: ${LOG_FILE}"
    else
        LOG_FILE="/var/log/vpn-placeholder-install-${DOMAIN}-${TIMESTAMP}.log"
        print_info "Инициализация лога: ${LOG_FILE}"
    fi

    # Create log file
    touch "$LOG_FILE" 2>/dev/null || {
        print_error "Не удалось создать лог-файл: ${LOG_FILE}"
        exit 1
    }

    # Redirect all output to log and console
    exec > >(tee -a "$LOG_FILE") 2>&1

    echo "=========================================="
    echo "VPN Placeholder Site Installation"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Domain: ${DOMAIN}"
    echo "Email: ${EMAIL}"
    echo "Dry run: ${DRY_RUN}"
    echo "=========================================="
    echo ""
}

# Backup Nginx configuration
backup_nginx_config() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 0
    fi

    local backup_dir="${NGINX_BACKUP_BASE}-${TIMESTAMP}"
    execute mkdir -p "$backup_dir"

    local filename=$(basename "$file")
    execute cp -a "$file" "${backup_dir}/${filename}"
    print_success "Создана резервная копия: ${backup_dir}/${filename}"
}

# Restore Nginx configuration on failure
restore_nginx_config() {
    local file="$1"
    local backup_dir="${NGINX_BACKUP_BASE}-${TIMESTAMP}"
    local filename=$(basename "$file")

    if [ -f "${backup_dir}/${filename}" ]; then
        execute cp -a "${backup_dir}/${filename}" "$file"
        print_warning "Восстановлена резервная копия: $file"
    fi
}

# Trap for unexpected failures
trap_error() {
    local line_number=$1
    print_error "Неожиданная ошибка на строке ${line_number}"
    print_info "Проверьте лог: ${LOG_FILE}"
    exit 1
}

trap 'trap_error ${LINENO}' ERR

# ============================================================================
# Step Functions
# ============================================================================

# Step 1: DNS Verification
step_dns_verification() {
    print_step "1️⃣ Проверка DNS"

    print_info "Убедитесь, что A-запись существует:"
    print_info "  ${DOMAIN} → <публичный IP сервера>"
    echo ""

    print_info "Проверка DNS..."

    # Check if dig is available
    if ! command -v dig >/dev/null 2>&1; then
        print_warning "Команда 'dig' не найдена, используется альтернативный метод"
        # Try with host command
        if command -v host >/dev/null 2>&1; then
            local dns_result
            dns_result=$(host -t A "${DOMAIN}" 2>&1 | grep "has address" | awk '{print $NF}' || echo "")

            if [ -z "$dns_result" ]; then
                if [ "$DRY_RUN" = false ]; then
                    print_error "DNS-запись для ${DOMAIN} не найдена!"
                    print_info "Пожалуйста, создайте A-запись, указывающую на IP этого сервера."
                    exit 1
                else
                    print_warning "DNS-запись не найдена (dry-run: продолжаем)"
                fi
            else
                print_success "DNS-запись найдена:"
                echo "$dns_result" | while read -r ip; do
                    echo "  ${DOMAIN} → ${ip}"
                done
            fi
        else
            print_warning "Утилиты для проверки DNS (dig/host) не найдены"
            if [ "$DRY_RUN" = false ]; then
                print_info "Установите dnsutils: apt-get install -y dnsutils"
                print_warning "Проверка DNS пропущена, убедитесь, что A-запись настроена вручную"
            fi
        fi
    else
        local dns_result
        dns_result=$(dig +short "${DOMAIN}" A 2>&1 || echo "")

        if [ -z "$dns_result" ]; then
            if [ "$DRY_RUN" = false ]; then
                print_error "DNS-запись для ${DOMAIN} не найдена!"
                print_info "Пожалуйста, создайте A-запись, указывающую на IP этого сервера."
                exit 1
            else
                print_warning "DNS-запись не найдена (dry-run: продолжаем)"
            fi
        else
            print_success "DNS-запись найдена:"
            echo "$dns_result" | while read -r ip; do
                echo "  ${DOMAIN} → ${ip}"
            done
        fi
    fi

    # Get server public IP
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "unknown")
    print_info "Публичный IP сервера: ${server_ip}"

    if [ "$server_ip" != "unknown" ] && [ -n "${dns_result:-}" ]; then
        if ! echo "$dns_result" | grep -q "$server_ip"; then
            print_warning "DNS не указывает на текущий IP сервера (${server_ip})"
            print_warning "Убедитесь, что A-запись настроена правильно"
        fi
    fi

    echo ""
    print_success "Шаг 1: DNS-проверка пройдена"
}

# Step 2: Install Nginx and Certbot
step_install_packages() {
    print_step "2️⃣ Установка Nginx и Certbot"

    print_info "Обновление списка пакетов..."
    execute env DEBIAN_FRONTEND=noninteractive apt-get update -qq

    print_info "Установка пакетов..."
    execute env DEBIAN_FRONTEND=noninteractive apt-get install -qq -y nginx certbot python3-certbot-nginx

    # Verification
    print_info "Проверка установки..."

    if [ "$DRY_RUN" = false ]; then
        if ! command -v nginx >/dev/null 2>&1; then
            print_error "nginx не установлен или недоступен в PATH"
            exit 1
        fi

        if ! command -v certbot >/dev/null 2>&1; then
            print_error "certbot не установлен или недоступен в PATH"
            exit 1
        fi

        local nginx_version
        nginx_version=$(nginx -v 2>&1 || echo "unknown")
        print_success "nginx установлен: ${nginx_version}"

        local certbot_version
        certbot_version=$(certbot --version 2>&1 | head -1 || echo "unknown")
        print_success "certbot установлен: ${certbot_version}"
    else
        echo "[DRY-RUN] Проверка установки nginx и certbot"
        print_success "В режиме dry-run проверка пропущена"
    fi

    echo ""
    print_success "Шаг 2: Установка завершена"
}

# Step 3: Remove default and create test page
step_prepare_site() {
    print_step "3️⃣ Удаление дефолта и создание тестовой страницы"

    print_info "Удаление дефолтной конфигурации Nginx..."
    if [ -f /etc/nginx/sites-enabled/default ]; then
        backup_nginx_config /etc/nginx/sites-enabled/default
        execute rm -f /etc/nginx/sites-enabled/default
        print_success "Удалён /etc/nginx/sites-enabled/default"
    else
        print_info "Дефолтная конфигурация уже удалена"
    fi

    print_info "Создание директории сайта..."
    execute mkdir -p "${SITE_ROOT}"

    print_info "Создание тестовой страницы..."
    execute bash -c "echo '<h1>ok</h1>' > ${SITE_ROOT}/index.html"

    print_info "Проверка созданных файлов..."
    execute ls -la "${SITE_ROOT}"

    # Verification
    if [ "$DRY_RUN" = false ]; then
        if [ ! -f "${SITE_ROOT}/index.html" ]; then
            print_error "Файл ${SITE_ROOT}/index.html не создан"
            exit 1
        fi

        if ! grep -q "ok" "${SITE_ROOT}/index.html"; then
            print_error "Содержимое ${SITE_ROOT}/index.html некорректно"
            exit 1
        fi

        print_success "Тестовая страница создана"
    else
        echo "[DRY-RUN] Проверка создания тестовой страницы"
        print_success "В режиме dry-run проверка пропущена"
    fi

    # Test Nginx configuration
    print_info "Проверка конфигурации Nginx..."
    if [ "$DRY_RUN" = false ]; then
        if ! nginx -t 2>&1; then
            print_error "Конфигурация Nginx содержит ошибки"
            restore_nginx_config /etc/nginx/sites-enabled/default
            exit 1
        fi
        print_success "Конфигурация Nginx корректна"
    else
        echo "[DRY-RUN] nginx -t"
    fi

    echo ""
    print_success "Шаг 3: Подготовка завершена"
}

# Step 3.5: Create temporary HTTP config for Certbot
step_create_temp_http_config() {
    print_step "3.5️⃣ Создание временной HTTP-конфигурации для Certbot"

    local temp_config="/etc/nginx/sites-available/temp-http-${DOMAIN}.conf"

    print_info "Создание временной конфигурации для порта 80..."

    # Backup if exists
    backup_nginx_config "${temp_config}"

    # Create temporary HTTP server block for certbot
    local temp_conf_content="server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root ${SITE_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Allow certbot to use webroot
    location ~ /.well-known {
        allow all;
    }
}"

    if [ "$DRY_RUN" = false ]; then
        echo "$temp_conf_content" > "${temp_config}"
        print_success "Создан ${temp_config}"
    else
        echo "[DRY-RUN] Создание ${temp_config} со следующим содержимым:"
        echo "$temp_conf_content"
    fi

    # Activate configuration
    print_info "Активация временной конфигурации..."
    execute ln -sf "${temp_config}" "/etc/nginx/sites-enabled/temp-http-${DOMAIN}.conf" 2>/dev/null || true

    # Test configuration
    print_info "Тестирование конфигурации Nginx..."
    if [ "$DRY_RUN" = false ]; then
        if ! nginx -t 2>&1; then
            print_error "Конфигурация Nginx содержит ошибки"
            restore_nginx_config "${temp_config}"
            exit 1
        fi
        print_success "Конфигурация Nginx корректна"
    else
        echo "[DRY-RUN] nginx -t"
    fi

    # Reload Nginx
    print_info "Перезагрузка Nginx..."
    execute systemctl reload nginx

    # Verification
    print_info "Проверка доступности сайта на порту 80..."
    if [ "$DRY_RUN" = false ]; then
        sleep 1
        if curl -sf "http://127.0.0.1/" -H "Host: ${DOMAIN}" | grep -q "ok"; then
            print_success "Сайт доступен на порту 80"
        else
            print_warning "Не удалось проверить доступность (это не критично)"
        fi
    else
        echo "[DRY-RUN] curl -sf http://127.0.0.1/ -H \"Host: ${DOMAIN}\""
    fi

    echo ""
    print_success "Шаг 3.5: Временная HTTP-конфигурация создана"
}

# Step 4: Obtain TLS certificate
step_obtain_certificate() {
    print_step "4️⃣ Получение TLS-сертификата"

    print_info "ВАЖНО: Убедитесь, что порт 80 открыт и доступен извне"
    print_info "Certbot должен иметь возможность связаться с сервером по HTTP"
    echo ""

    print_info "Запуск Certbot с флагом --nginx..."
    print_info "Команда: certbot --nginx -d ${DOMAIN} --agree-tos -m ${EMAIL} --non-interactive"

    if [ "$DRY_RUN" = false ]; then
        if ! certbot --nginx -d "${DOMAIN}" --agree-tos -m "${EMAIL}" --non-interactive; then
            print_error "Ошибка получения сертификата"
            print_info "Возможные причины:"
            print_info "  - Порт 80 закрыт или недоступен извне"
            print_info "  - DNS не указывает на этот сервер"
            print_info "  - Лимит запросов Let's Encrypt исчерпан"
            exit 1
        fi
    else
        echo "[DRY-RUN] certbot --nginx -d ${DOMAIN} --agree-tos -m ${EMAIL} --non-interactive"
    fi

    # Verification
    local cert_dir="/etc/letsencrypt/live/${DOMAIN}"

    if [ "$DRY_RUN" = false ]; then
        if [ ! -d "$cert_dir" ]; then
            print_error "Директория сертификата не найдена: ${cert_dir}"
            exit 1
        fi

        if [ ! -f "${cert_dir}/fullchain.pem" ]; then
            print_error "Файл fullchain.pem не найден"
            exit 1
        fi

        if [ ! -f "${cert_dir}/privkey.pem" ]; then
            print_error "Файл privkey.pem не найден"
            exit 1
        fi

        print_success "Сертификаты установлены:"
        execute ls -l "${cert_dir}/"
    else
        echo "[DRY-RUN] Проверка установки сертификатов в ${cert_dir}"
        print_success "В режиме dry-run проверка пропущена"
    fi

    echo ""
    print_success "Шаг 4: Сертификат получен"
}

# Step 5: Configure SNI site
step_configure_sni() {
    print_step "5️⃣ Конфигурация SNI-сайта (порт 8443 + Proxy Protocol)"

    # Remove temporary HTTP config created for certbot
    print_info "Удаление временной HTTP-конфигурации..."
    local temp_config_enabled="/etc/nginx/sites-enabled/temp-http-${DOMAIN}.conf"
    local temp_config_available="/etc/nginx/sites-available/temp-http-${DOMAIN}.conf"

    if [ -L "$temp_config_enabled" ] || [ -f "$temp_config_enabled" ]; then
        execute rm -f "$temp_config_enabled"
        print_success "Удалена активированная временная конфигурация"
    fi

    if [ -f "$temp_config_available" ]; then
        execute rm -f "$temp_config_available"
        print_success "Удалена временная конфигурация из sites-available"
    fi

    print_info "Создание конфигурации: ${SNI_CONFIG}"

    # Backup existing config if present
    backup_nginx_config "${SNI_CONFIG}"

    # Create SNI configuration
    local sni_conf_content="server {
  listen 127.0.0.1:8443 ssl http2 proxy_protocol;
  server_name ${DOMAIN};

  ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;
  ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
  ssl_session_cache shared:SSL:1m;
  ssl_session_timeout 1d;
  ssl_session_tickets off;

  real_ip_header proxy_protocol;
  set_real_ip_from 127.0.0.1;
  set_real_ip_from ::1;

  root ${SITE_ROOT};
  index index.html;

  location / {
    try_files \$uri \$uri/ =404;
  }
}"

    if [ "$DRY_RUN" = false ]; then
        echo "$sni_conf_content" > "${SNI_CONFIG}"
        print_success "Создан ${SNI_CONFIG}"
    else
        echo "[DRY-RUN] Создание ${SNI_CONFIG} со следующим содержимым:"
        echo "$sni_conf_content"
    fi

    # Activate configuration
    print_info "Активация конфигурации..."
    execute ln -sf "${SNI_CONFIG}" /etc/nginx/sites-enabled/ 2>/dev/null || true

    # Test configuration
    print_info "Тестирование конфигурации Nginx..."
    if [ "$DRY_RUN" = false ]; then
        if ! nginx -t 2>&1; then
            print_error "Конфигурация Nginx содержит ошибки"
            restore_nginx_config "${SNI_CONFIG}"
            exit 1
        fi
        print_success "Конфигурация Nginx корректна"
    else
        echo "[DRY-RUN] nginx -t"
    fi

    # Restart Nginx
    print_info "Перезапуск Nginx..."
    execute systemctl restart nginx

    # Wait for Nginx to start
    if [ "$DRY_RUN" = false ]; then
        sleep 2
    fi

    # Verification
    print_info "Проверка прослушивания порта 8443..."
    if [ "$DRY_RUN" = false ]; then
        if ! ss -ltnp | grep -q "127.0.0.1:8443"; then
            print_error "Nginx не слушает на 127.0.0.1:8443"
            print_info "Вывод ss -ltnp:"
            ss -ltnp | grep -E "(8443|nginx)" || true
            exit 1
        fi
        print_success "Nginx слушает на 127.0.0.1:8443"
        ss -ltnp | grep "127.0.0.1:8443"
    else
        echo "[DRY-RUN] ss -ltnp | grep 8443"
    fi

    echo ""
    print_success "Шаг 5: SNI-конфигурация завершена"
}

# Step 5.1: Deploy static site from GitHub
step_deploy_static_site() {
    print_step "5.1️⃣ Развёртывание статического сайта из GitHub"

    print_info "Репозиторий: https://github.com/${GITHUB_REPO}"
    print_info "Ветка: ${GITHUB_BRANCH}"

    # Create temporary directory
    local tmpdir
    tmpdir=$(mktemp -d)
    print_info "Временная директория: ${tmpdir}"

    # Download tarball
    print_info "Загрузка архива..."
    local tarball_url="https://codeload.github.com/${GITHUB_REPO}/tar.gz/refs/heads/${GITHUB_BRANCH}"

    if [ "$DRY_RUN" = false ]; then
        if ! curl -fsSL "${tarball_url}" -o "${tmpdir}/site.tar.gz"; then
            print_error "Не удалось загрузить архив из ${tarball_url}"
            rm -rf "${tmpdir}"
            exit 1
        fi
        print_success "Архив загружен"
    else
        echo "[DRY-RUN] curl -fsSL ${tarball_url} -o ${tmpdir}/site.tar.gz"
    fi

    # Extract tarball
    print_info "Распаковка архива..."
    execute tar -xzf "${tmpdir}/site.tar.gz" -C "${tmpdir}"

    # Find extracted directory
    local extracted_dir="${tmpdir}/temp-vpn-site-${GITHUB_BRANCH}"

    if [ "$DRY_RUN" = false ] && [ ! -d "$extracted_dir" ]; then
        print_error "Распакованная директория не найдена: ${extracted_dir}"
        rm -rf "${tmpdir}"
        exit 1
    fi

    # Deploy to site root
    print_info "Копирование файлов в ${SITE_ROOT}..."

    if command -v rsync >/dev/null 2>&1; then
        print_info "Используется rsync..."
        execute rsync -a --delete "${extracted_dir}/" "${SITE_ROOT}/"
    else
        print_warning "rsync не найден, используется cp..."
        if [ "$DRY_RUN" = false ]; then
            rm -rf "${SITE_ROOT:?}"/*
            cp -a "${extracted_dir}/"* "${SITE_ROOT}/"
        else
            echo "[DRY-RUN] rm -rf ${SITE_ROOT}/* && cp -a ${extracted_dir}/* ${SITE_ROOT}/"
        fi
    fi

    print_success "Файлы скопированы"

    # Cleanup
    print_info "Очистка временных файлов..."
    execute rm -rf "${tmpdir}"

    # Verification
    print_info "Проверка развёрнутого сайта..."

    if [ "$DRY_RUN" = false ]; then
        if [ ! -f "${SITE_ROOT}/index.html" ]; then
            print_error "Файл ${SITE_ROOT}/index.html не найден после развёртывания"
            exit 1
        fi

        if grep -q "^<h1>ok</h1>$" "${SITE_ROOT}/index.html" 2>/dev/null; then
            print_error "Сайт всё ещё содержит тестовую страницу 'ok'"
            exit 1
        fi

        print_success "Файл index.html обновлён"
    else
        echo "[DRY-RUN] Проверка развёртывания статического сайта"
        print_success "В режиме dry-run проверка пропущена"
    fi

    # Test site via curl
    print_info "Тестирование сайта через curl..."
    if [ "$DRY_RUN" = false ]; then
        local test_output
        test_output=$(curl -sS --resolve "${DOMAIN}:8443:127.0.0.1" "https://${DOMAIN}:8443/" 2>&1 | head -n 3)

        if [ -z "$test_output" ]; then
            print_error "Не удалось получить содержимое сайта"
            print_info "Попробуйте выполнить вручную:"
            print_info "  curl -sS --resolve ${DOMAIN}:8443:127.0.0.1 https://${DOMAIN}:8443/"
            exit 1
        fi

        print_success "Сайт отвечает:"
        echo "$test_output"
    else
        echo "[DRY-RUN] curl -sS --resolve ${DOMAIN}:8443:127.0.0.1 https://${DOMAIN}:8443/ | head -n 3"
    fi

    echo ""
    print_success "Шаг 5.1: Сайт развёрнут"
}

# Step 6: Reality/3x-ui reminder
step_reality_reminder() {
    print_step "6️⃣ Напоминание про Reality (3x-ui) inbound"

    print_info "Скрипт НЕ изменяет конфигурацию 3x-ui."
    print_info "Пожалуйста, настройте Reality inbound вручную в панели 3x-ui:"
    echo ""

    cat <<EOF
┌─────────────────────┬────────────────────────────────────────┐
│ Поле                │ Значение                               │
├─────────────────────┼────────────────────────────────────────┤
│ Port                │ 443                                    │
│ Security            │ reality                                │
│ Dest (Target)       │ 127.0.0.1:8443                         │
│ SNI / Server name   │ ${DOMAIN}                              │
│ uTLS                │ chrome                                 │
│ Xver                │ 1                                      │
└─────────────────────┴────────────────────────────────────────┘
EOF

    echo ""
    print_info "Команды для проверки (выполните вручную):"
    echo ""
    echo "  # Проверка TLS через openssl:"
    echo "  openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} -alpn h2 -brief </dev/null"
    echo ""
    echo "  # Проверка локального сайта:"
    echo "  curl -vk https://127.0.0.1:8443 --resolve ${DOMAIN}:8443:127.0.0.1 | head -n 30"
    echo ""

    print_success "Шаг 6: Напоминание выведено"
}

# Step 7: Enable certbot auto-renewal
step_enable_renewal() {
    print_step "7️⃣ Автопродление сертификата"

    print_info "Включение таймера certbot..."
    execute systemctl enable certbot.timer
    execute systemctl start certbot.timer

    # Verification
    print_info "Проверка статуса таймера..."
    if [ "$DRY_RUN" = false ]; then
        if systemctl is-active --quiet certbot.timer; then
            print_success "certbot.timer активен"
            systemctl status certbot.timer --no-pager | head -5
        else
            print_warning "certbot.timer не активен"
            print_info "Выполните вручную: systemctl start certbot.timer"
        fi
    else
        echo "[DRY-RUN] systemctl is-active certbot.timer"
    fi

    echo ""
    print_success "Шаг 7: Автопродление настроено"
}

# Final checklist
final_checklist() {
    print_step "✅ Финальная проверка"

    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│ Checklist:                                                      │"
    echo "├─────────────────────────────────────────────────────────────────┤"

    # DNS
    if dig +short "${DOMAIN}" A >/dev/null 2>&1; then
        echo "│ ✓ DNS запись существует                                        │"
    else
        echo "│ ✗ DNS запись не найдена                                        │"
    fi

    # Certificate
    if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
        echo "│ ✓ TLS-сертификат установлен                                    │"
    else
        echo "│ ✗ TLS-сертификат отсутствует                                   │"
    fi

    # SNI config
    if [ -f "${SNI_CONFIG}" ] && [ -L /etc/nginx/sites-enabled/sni.conf ]; then
        echo "│ ✓ SNI-конфигурация создана и активирована                      │"
    else
        echo "│ ✗ SNI-конфигурация отсутствует                                 │"
    fi

    # Port 8443
    if [ "$DRY_RUN" = false ]; then
        if ss -ltnp | grep -q "127.0.0.1:8443"; then
            echo "│ ✓ Nginx слушает на 127.0.0.1:8443                              │"
        else
            echo "│ ✗ Порт 8443 не прослушивается                                  │"
        fi
    else
        echo "│ ? Порт 8443 (не проверено в режиме dry-run)                    │"
    fi

    # Static site
    if [ -f "${SITE_ROOT}/index.html" ] && [ -f "${SITE_ROOT}/assets/site.css" ]; then
        echo "│ ✓ Статический сайт развёрнут                                   │"
    else
        echo "│ ✗ Статический сайт не развёрнут                                │"
    fi

    # Certbot timer
    if [ "$DRY_RUN" = false ]; then
        if systemctl is-active --quiet certbot.timer; then
            echo "│ ✓ Автопродление certbot активно                                │"
        else
            echo "│ ⚠ Автопродление certbot неактивно                              │"
        fi
    else
        echo "│ ? Автопродление (не проверено в режиме dry-run)                │"
    fi

    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""

    print_success "Установка завершена!"
    echo ""
    print_info "Следующие шаги:"
    echo "  1. Настройте Reality inbound в панели 3x-ui (см. таблицу выше)"
    echo "  2. Проверьте доступность сайта извне: https://${DOMAIN}/"
    echo "  3. Протестируйте VPN-подключение"
    echo ""
}

# Print log download command
print_log_info() {
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "SERVER_IP")

    echo ""
    echo "=========================================="
    echo "Лог сохранён: ${LOG_FILE}"
    echo ""
    echo "Для загрузки лога выполните:"
    echo "  scp root@${server_ip}:\"${LOG_FILE}\" ."
    echo "=========================================="
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --email)
                EMAIL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                print_error "Неизвестный параметр: $1"
                echo "Используйте --help для справки"
                exit 1
                ;;
        esac
    done
}

# Interactive prompt for domain
prompt_domain() {
    if [ -z "$DOMAIN" ]; then
        echo ""
        read -rp "Введите домен (например, video.mashina.online): " DOMAIN

        if [ -z "$DOMAIN" ]; then
            print_error "Домен не может быть пустым"
            exit 1
        fi
    fi
}

# Prompt for email or use default
prompt_email() {
    if [ -z "$EMAIL" ]; then
        echo ""
        read -rp "Введите email для уведомлений Let's Encrypt (Enter для admin@${DOMAIN}): " EMAIL

        # If still empty after prompt, use default
        if [ -z "$EMAIL" ]; then
            EMAIL="admin@${DOMAIN}"
            print_info "Используется email по умолчанию: ${EMAIL}"
        fi
    fi
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    echo "=========================================="
    echo "VPN Placeholder Site Installation Script"
    echo "Version: ${SCRIPT_VERSION}"
    echo "=========================================="

    # Parse arguments
    parse_arguments "$@"

    # Check root
    check_root

    # Prompt for domain if not provided
    prompt_domain

    # Prompt for email
    prompt_email

    # Initialize log
    init_log

    # Execute steps
    step_dns_verification
    step_install_packages
    step_prepare_site
    step_create_temp_http_config
    step_obtain_certificate
    step_configure_sni
    step_deploy_static_site
    step_reality_reminder
    step_enable_renewal

    # Final checklist
    final_checklist

    # Print log information
    print_log_info

    echo ""
    print_success "Все шаги выполнены успешно!"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
