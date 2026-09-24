# MoyKabinet Server · ASP.NET Core 10

Если сервер нужен для защиты или экзамена, начните с [русской шпаргалки по архитектуре](EXAM_GUIDE_RU.md).
Подробное объяснение базы, Identity, токенов, SMTP, OAuth и DI находится в [разборе Infrastructure](INFRASTRUCTURE_GUIDE_RU.md).
Разбор `Program.cs`, middleware, Minimal API и всех маршрутов находится в [конспекте по API](API_GUIDE_RU.md).

Продовый backend приложения на .NET 10 LTS. Решение разделено на `Domain`, `Application`, `Infrastructure` и HTTP API. ASP.NET Core Identity отвечает за хеширование паролей и блокировку перебора; EF Core хранит аккаунты, сессии, кабинеты, ревизии синхронизации и идемпотентные онлайн-записи в SQLite.

## Локальный запуск

Нужен .NET SDK 10:

```sh
dotnet run --project src/MoyKabinet.Api
```

Профиль разработки запускает API на `http://127.0.0.1:8787`. Скрипт `./run-server.sh` оставлен как дополнительный способ запуска.
Swagger UI в Development доступен по адресу `http://127.0.0.1:8787/swagger`. В Production он отключён, чтобы публично не раскрывать полную схему приватного API.

В Development код подтверждения email пишется только в серверный лог. В Production отсутствие SMTP считается ошибкой, и аккаунт без реального письма не создаётся.

```sh
dotnet test MoyKabinet.Server.slnx
dotnet ef database update --project src/MoyKabinet.Infrastructure --startup-project src/MoyKabinet.Api
```

## Конфигурация Production

Настройки передаются переменными окружения с двойным подчёркиванием:

| Назначение | Переменные |
|---|---|
| База | `ConnectionStrings__Database=Data Source=/data/moykabinet.db` |
| Ключи шифрования | `DataProtection__KeysPath=/data/keys` — каталог должен сохраняться вместе с volume |
| Публичный host | `AllowedHosts=booking.example.com` — точное имя вашего домена |
| SMTP | `Email__SmtpHost`, `Email__SmtpPort`, `Email__UseTls`, `Email__Username`, `Email__Password`, `Email__From` |
| Google | `Auth__Google__ClientId`, `Auth__Google__ClientSecret`, `Auth__Google__RedirectUris` |
| Яндекс | `Auth__Yandex__ClientId`, `Auth__Yandex__ClientSecret`, `Auth__Yandex__RedirectUris` |
| Apple | `Auth__Apple__ClientId`, `Auth__Apple__TeamId`, `Auth__Apple__KeyId`, `Auth__Apple__PrivateKey` |
| Reverse proxy | `ReverseProxy__KnownProxies__0` и следующие адреса доверенных прокси |

Списки Redirect URI разделяются запятыми. Приватный ключ Apple можно передать с `\n` вместо переносов строк. Скопируйте `.env.example` в локальный `production.env`, заполните значения и не добавляйте этот файл в Git. Секреты нельзя хранить в `appsettings.json` или Xcode-проекте.

## Контуры защиты

- email подтверждается одноразовым шестизначным кодом со сроком 10 минут и лимитом попыток;
- пароль: от 10 символов, верхний/нижний регистр, цифра и специальный символ;
- после пяти неверных паролей вход блокируется на 15 минут;
- access token живёт 1 час, rotating refresh token — 90 дней; в SQLite хранятся только SHA-256 хеши;
- смена пароля отзывает все сессии; удаление аккаунта удаляет сессии и связи, а Apple refresh token отзывается у Apple;
- внешние токены Apple в базе защищены ASP.NET Data Protection, ключи вынесены в отдельный постоянный volume;
- OAuth JWT проверяются по подписи, issuer, audience и сроку; Redirect URI сверяется с allowlist;
- API ограничен по частоте, аккаунт может связать до 20 кабинетов, размер запроса — 50 МБ, ошибки не возвращают stack trace;
- синхронизация использует ревизию и optimistic concurrency, публичная запись — request ID для идемпотентности.

## Docker

```sh
docker build -t moykabinet-api .
docker run -d --restart unless-stopped --name moykabinet-api \
  -p 127.0.0.1:8787:8080 \
  -v moykabinet-data:/data \
  --env-file production.env moykabinet-api
```

Перед контейнером нужен HTTPS reverse proxy. Резервируйте `/data/moykabinet.db` через SQLite backup API и обязательно сохраняйте `/data/keys`: без ключей нельзя расшифровать сохранённый Apple refresh token для отзыва при удалении аккаунта.

## Основные маршруты

- `POST /api/auth/register`, `/confirm`, `/login`, `/refresh`, `/logout`;
- `POST /api/auth/password/reset/request`, `/confirm`;
- `POST /api/auth/exchange`, `/apple`; `GET/DELETE /api/auth/me`;
- `POST /api/cabinets`, `GET/PUT /api/cabinets/{id}/state`, `DELETE /api/cabinets/{id}`;
- `GET /api/public/{id}`, `GET /api/public/{id}/slots`, `POST /api/public/{id}/book`;
- `GET /health`.

Миграции лежат в `src/MoyKabinet.Infrastructure/Migrations`. При обновлении сначала делайте резервную копию, затем запускайте `dotnet ef database update` или отдельный миграционный job.
