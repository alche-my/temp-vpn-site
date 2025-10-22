# Статический Placeholder-сайт

Лёгкий, автономный статический сайт-заглушка на русском языке, предназначенный для создания впечатления полноценного работающего сайта при проверках DPI/TSPI через SNI.

## Особенности

- **Полностью автономный**: нет внешних зависимостей, CDN, аналитики или трекеров
- **Минимальный вес**: один HTML + 3 небольших ресурса (CSS, JS, SVG)
- **Современный дизайн**: градиентный фон, чистая типографика, адаптивная вёрстка
- **Темная тема**: автоматическая поддержка `prefers-color-scheme`
- **Доступность**: семантическая разметка, ARIA-метки, состояния фокуса
- **SEO-нейтральный**: нет аналитики, метатегов Open Graph или robots.txt

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
└── README.md           # Этот файл
```

## Развёртывание

### Шаг 1: Копирование файлов

Скопируйте все файлы в директорию на сервере:

```bash
# Создайте директорию
sudo mkdir -p /var/www/placeholder

# Скопируйте файлы (замените путь на ваш)
sudo cp -r * /var/www/placeholder/

# Установите права
sudo chown -R www-data:www-data /var/www/placeholder
sudo chmod -R 755 /var/www/placeholder
```

### Шаг 2: Настройка Nginx

Отредактируйте конфигурацию Nginx:

```bash
# Создайте конфигурационный файл
sudo nano /etc/nginx/sites-available/placeholder

# Вставьте содержимое из nginx.conf (не забудьте заменить example.com на ваш домен)
```

Основные настройки в `nginx.conf`:

- Замените `server_name example.com` на ваш домен
- Укажите путь к SSL-сертификатам (если не настроены глобально)
- Измените `root /var/www/placeholder` при необходимости

Активируйте конфигурацию:

```bash
# Создайте символическую ссылку
sudo ln -s /etc/nginx/sites-available/placeholder /etc/nginx/sites-enabled/

# Проверьте конфигурацию
sudo nginx -t

# Перезагрузите Nginx
sudo systemctl reload nginx
```

### Шаг 3: Проверка TLS (если ещё не настроен)

Если у вас ещё нет SSL-сертификатов, используйте Let's Encrypt:

```bash
# Установите certbot
sudo apt install certbot python3-certbot-nginx

# Получите сертификат
sudo certbot --nginx -d example.com
```

## Валидация и проверка

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

### Nginx не запускается после изменения конфигурации

```bash
# Проверьте синтаксис
sudo nginx -t

# Просмотрите логи ошибок
sudo tail -f /var/log/nginx/error.log
```

### Файлы не отдаются (404)

Проверьте права доступа:

```bash
ls -la /var/www/placeholder
# Все файлы должны быть читаемыми для www-data
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