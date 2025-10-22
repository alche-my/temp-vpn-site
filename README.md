# Статический Placeholder-сайт

Лёгкий, автономный статический сайт-заглушка на русском языке, предназначенный для создания впечатления полноценного работающего сайта при проверках DPI/TSPI через SNI.

## Особенности

- **Полностью автономный**: нет внешних зависимостей, CDN, аналитики или трекеров
- **Минимальный вес**: один HTML + 3 небольших ресурса (CSS, JS, SVG)
- **Современный дизайн**: градиентный фон, чистая типографика, адаптивная вёрстка
- **Темная тема**: автоматическая поддержка `prefers-color-scheme`
- **Доступность**: семантическая разметка, ARIA-метки, состояния фокуса
- **SEO-нейтральный**: нет аналитики, метатегов Open Graph или robots.txt
- **Автоматическая установка**: готовый bash-скрипт для полного развёртывания

## Структура файлов

```
/
├── index.html          # Главная HTML-страница
├── favicon.ico         # Иконка сайта
├── assets/
│   ├── site.css        # Стили с градиентом и темной темой
│   ├── app.js          # Минимальный JS для отображения домена
│   └── logo.svg        # Логотип (встроенный SVG)
├── nginx.conf          # Пример конфигурации Nginx
├── install.sh          # Скрипт автоматической установки (рекомендуется)
└── README.md           # Этот файл
```

## Быстрый старт (рекомендуется)

### Автоматическая установка

Используйте скрипт `install.sh` для полностью автоматического развёртывания:

**Интерактивный режим:**
```bash
# Скачать и запустить скрипт
bash -c "$(curl -fsSL https://raw.githubusercontent.com/alche-my/temp-vpn-site/main/install.sh)"

# Или скачать сначала
curl -fsSL https://raw.githubusercontent.com/alche-my/temp-vpn-site/main/install.sh -o install.sh
chmod +x install.sh
sudo ./install.sh
```

**Неинтерактивный режим:**
```bash
curl -fsSL https://raw.githubusercontent.com/alche-my/temp-vpn-site/main/install.sh | sudo bash -s -- \
  --domain video.mashina.online \
  --email admin@video.mashina.online
```

**Тестовый прогон (без изменений системы):**
```bash
./install.sh --domain example.com --dry-run
```

### Что делает install.sh

Скрипт автоматически выполняет все необходимые шаги:

1. ✅ **Проверка DNS**: убеждается, что A-запись существует
2. ✅ **Установка пакетов**: устанавливает Nginx и Certbot
3. ✅ **Подготовка сайта**: удаляет дефолтную конфигурацию, создаёт директорию
3.5. ✅ **Временная HTTP-конфигурация**: создаёт nginx config на порту 80 для Certbot
4. ✅ **Получение TLS-сертификата**: использует Certbot с флагом `--nginx`
5. ✅ **Настройка SNI**: удаляет временный config, создаёт конфигурацию на `127.0.0.1:8443` с Proxy Protocol
6. ✅ **Развёртывание сайта**: скачивает и устанавливает файлы из GitHub
7. ✅ **Настройка автопродления**: включает таймер Certbot для обновления сертификатов
8. ✅ **Финальная проверка**: выводит чеклист и инструкции для 3x-ui/Reality

**Особенности скрипта:**
- Интерактивные запросы домена и email (или автоматический режим с флагами)
- Полное логирование в `/var/log/vpn-placeholder-install-<domain>-<timestamp>.log`
- Автоматический бэкап конфигураций Nginx
- Откат изменений при ошибках
- Проверка после каждого шага с понятными сообщениями об ошибках
- Режим `--dry-run` для тестирования без изменений
- Напоминание о настройке Reality/3x-ui inbound

### Конфигурация Reality (3x-ui)

После завершения установки настройте Reality inbound в панели 3x-ui:

| Поле              | Значение          |
|-------------------|-------------------|
| Port              | 443               |
| Security          | reality           |
| Dest (Target)     | 127.0.0.1:8443    |
| SNI / Server name | ваш_домен         |
| uTLS              | chrome            |
| Xver              | 1                 |

**Команды для проверки:**
```bash
# Проверка TLS
openssl s_client -connect ваш_домен:443 -servername ваш_домен -alpn h2 -brief </dev/null

# Проверка локального сайта
curl -vk https://127.0.0.1:8443 --resolve ваш_домен:8443:127.0.0.1 | head -n 30
```

---

## Ручное развёртывание (альтернативный метод)

Если вы предпочитаете ручную установку вместо автоматического скрипта:

### Шаг 1: Копирование файлов

Скопируйте все файлы в директорию на сервере:

```bash
# Создайте директорию
sudo mkdir -p /var/www/html/site

# Скопируйте файлы (замените путь на ваш)
sudo cp -r * /var/www/html/site/

# Установите права
sudo chown -R www-data:www-data /var/www/html/site
sudo chmod -R 755 /var/www/html/site
```

### Шаг 2: Настройка Nginx

**Примечание:** Файл `nginx.conf` в репозитории — это справочный пример для обычного развёртывания. Для Reality/VLESS используйте конфигурацию SNI на порту 8443 с Proxy Protocol (создаётся автоматически скриптом `install.sh`).

Для ручной настройки SNI-сайта создайте конфигурацию `/etc/nginx/sites-available/sni.conf`:

```nginx
server {
  listen 127.0.0.1:8443 ssl http2 proxy_protocol;
  server_name ваш_домен;

  ssl_certificate     /etc/letsencrypt/live/ваш_домен/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/ваш_домен/privkey.pem;

  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;
  ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
  ssl_session_cache shared:SSL:1m;
  ssl_session_timeout 1d;
  ssl_session_tickets off;

  real_ip_header proxy_protocol;
  set_real_ip_from 127.0.0.1;
  set_real_ip_from ::1;

  root /var/www/html/site;
  index index.html;

  location / {
    try_files $uri $uri/ =404;
  }
}
```

Активируйте конфигурацию:

```bash
# Создайте символическую ссылку
sudo ln -s /etc/nginx/sites-available/sni.conf /etc/nginx/sites-enabled/

# Проверьте конфигурацию
sudo nginx -t

# Перезагрузите Nginx
sudo systemctl restart nginx

# Проверьте прослушивание порта 8443
ss -ltnp | grep 8443
```

### Шаг 3: Получение TLS-сертификата

Если у вас ещё нет SSL-сертификатов, используйте Let's Encrypt:

```bash
# Установите certbot
sudo apt install certbot python3-certbot-nginx

# Получите сертификат
sudo certbot --nginx -d example.com
```

## Валидация и проверка

**Примечание:** Если вы использовали `install.sh`, эти проверки выполняются автоматически. Данный раздел полезен для ручной установки и диагностики проблем.

После развёртывания выполните следующие проверки, чтобы убедиться, что сайт выглядит "настоящим" для автоматических систем.

### 1. Проверка TLS/ALPN и SNI

Убедитесь, что TLS работает корректно с HTTP/2:

```bash
openssl s_client -connect example.com:443 -servername example.com -alpn h2 -tls1_3 -brief </dev/null
```

**Ожидаемый результат**: Успешное подключение с протоколом `h2` (HTTP/2).

### 2. Проверка HTTP-заголовков

Проверьте, что сервер возвращает 200 OK:

```bash
curl -vkI https://example.com/
```

**Ожидаемый результат**:
- Статус: `HTTP/2 200`
- Заголовки: `content-type: text/html`, `cache-control`, `x-frame-options`, и т.д.

### 3. Проверка содержимого HTML

Получите первые 30 строк HTML:

```bash
curl -vk https://example.com/ | head -n 30
```

**Ожидаемый результат**: Валидный HTML с `<!DOCTYPE html>`, заголовком "Ой, что-то сломалось", и структурой страницы.

### 4. Проверка статических ресурсов

Убедитесь, что CSS, JS и SVG возвращаются с правильными заголовками кеширования:

```bash
# CSS
curl -vkI https://example.com/assets/site.css

# JavaScript
curl -vkI https://example.com/assets/app.js

# Logo SVG
curl -vkI https://example.com/assets/logo.svg

# Favicon
curl -vkI https://example.com/favicon.ico
```

**Ожидаемый результат**:
- Статус: `HTTP/2 200`
- Заголовок: `cache-control: public, max-age=604800, immutable`
- Соответствующие MIME-типы (text/css, application/javascript, image/svg+xml, image/x-icon)

### 5. Проверка "поддельных" подстраниц

Все пути должны возвращать `index.html` (выглядит как SPA):

```bash
curl -vkI https://example.com/about
curl -vkI https://example.com/contact
curl -vkI https://example.com/status
curl -vkI https://example.com/документы
```

**Ожидаемый результат**: Все возвращают `HTTP/2 200` с `content-type: text/html` (index.html).

### 6. Проверка отсутствия внешних запросов

Откройте сайт в браузере и проверьте DevTools → Network:

1. Откройте Developer Tools (F12)
2. Перейдите на вкладку Network
3. Загрузите страницу
4. Убедитесь, что все запросы идут только к вашему домену (нет CDN, Google Fonts, аналитики)

**Ожидаемый результат**: Только 4-5 запросов, все к `example.com`:
- `GET /` (HTML)
- `GET /assets/site.css`
- `GET /assets/app.js`
- `GET /assets/logo.svg`
- `GET /favicon.ico`

### 7. Проверка отображения домена

Откройте сайт в браузере и убедитесь, что в секции "Домен:" отображается ваш текущий домен (например, `example.com`).

## Устранение неполадок

### Проверка логов install.sh

Если автоматическая установка завершилась с ошибкой, проверьте лог:

```bash
# Лог находится в /var/log/vpn-placeholder-install-<domain>-<timestamp>.log
ls -lt /var/log/vpn-placeholder-install-*.log | head -1

# Просмотрите последний лог
sudo less $(ls -t /var/log/vpn-placeholder-install-*.log | head -1)
```

### Nginx не запускается после изменения конфигурации

```bash
# Проверьте синтаксис
sudo nginx -t

# Просмотрите логи ошибок
sudo tail -f /var/log/nginx/error.log

# Проверьте статус сервиса
sudo systemctl status nginx
```

### Файлы не отдаются (404)

Проверьте права доступа и местоположение файлов:

```bash
# Для установки через install.sh
ls -la /var/www/html/site
# Все файлы должны быть читаемыми для www-data

# Проверьте, что index.html существует
cat /var/www/html/site/index.html | head -5
```

### Порт 8443 не прослушивается

Проверьте конфигурацию и статус Nginx:

```bash
# Проверьте, что Nginx слушает на 127.0.0.1:8443
ss -ltnp | grep 8443

# Проверьте SNI-конфигурацию
cat /etc/nginx/sites-available/sni.conf

# Убедитесь, что конфигурация активирована
ls -l /etc/nginx/sites-enabled/sni.conf
```

### CSS/JS не загружаются

Проверьте MIME-типы в конфигурации Nginx и убедитесь, что `gzip` включен для соответствующих типов.

### Сертификат SSL не работает

Убедитесь, что certbot успешно выпустил сертификат:

```bash
sudo certbot certificates
```

## Технические детали

### Безопасность

- Нет внешних зависимостей (защита от supply chain атак)
- Стандартные заголовки безопасности (X-Frame-Options, X-Content-Type-Options, etc.)
- Нет встроенных скриптов или стилей (можно добавить CSP при желании)
- Скрытие скрытых файлов через Nginx (`location ~ /\.`)

### Производительность

- Весь сайт весит менее 20 КБ
- Статические ресурсы кешируются на 7 дней
- Gzip-сжатие для текстовых файлов
- HTTP/2 для мультиплексирования запросов
- Один HTML + 3 ресурса = минимум round-trips

### Доступность

- Семантическая HTML5-разметка
- ARIA-метки для навигации
- Поддержка клавиатурной навигации
- Видимые состояния фокуса
- Поддержка `prefers-reduced-motion`
- Адаптивный дизайн (mobile-first)

### Совместимость

Сайт работает во всех современных браузерах:
- Chrome/Edge 90+
- Firefox 88+
- Safari 14+
- Opera 76+

## Лицензия

Этот код предоставляется "как есть" без каких-либо гарантий.

## Контакты

Для вопросов и предложений используйте форму обратной связи на сайте.