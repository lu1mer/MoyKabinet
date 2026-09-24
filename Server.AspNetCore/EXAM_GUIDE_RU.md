# Шпаргалка по ASP.NET-серверу «Мой кабинет»

## 1. Что это за сервер

Это HTTP REST API на ASP.NET Core 10. Он принимает JSON-запросы от iOS-приложения, выполняет регистрацию и вход, хранит аккаунты и кабинеты в SQLite, синхронизирует расписание и обслуживает публичную страницу онлайн-записи.

На сервере **нет MVVM**, потому что MVVM решает задачу состояния пользовательского интерфейса. Здесь используется слоистая Clean Architecture:

```text
iPhone / браузер
       │ HTTP + JSON
       ▼
MoyKabinet.Api                 маршруты и HTTP-ответы
       │
       ▼
MoyKabinet.Application         контракты, DTO, интерфейсы, сценарии системы
       ▲
       │ реализует
MoyKabinet.Infrastructure      EF Core, SQLite, Identity, SMTP, OAuth, токены
       │
       ▼
MoyKabinet.Domain              основные сущности предметной области
```

Главное правило зависимостей: внутренние слои не должны знать о внешних деталях. `Domain` не знает про ASP.NET, HTTP и SQLite. `Application` знает предметные типы и объявляет интерфейсы. `Infrastructure` реализует эти интерфейсы. `Api` собирает всё приложение и принимает запросы.

## 2. Аналогии с iOS

| ASP.NET | Примерная аналогия в iOS |
|---|---|
| Endpoint | обработчик deep link или метод API router |
| DTO / `record` | `Codable struct` для запроса или ответа |
| Service | UseCase / Repository implementation |
| Interface | Swift `protocol` |
| Dependency Injection | передача зависимостей через `init`, только контейнер делает это автоматически |
| `DbContext` | единая точка работы с Core Data context |
| `DbSet<Cabinet>` | коллекция сущностей вроде fetchable entity set |
| EF Core migration | изменение Core Data schema с миграцией |
| Middleware | цепочка interceptors перед обработчиком запроса |
| `async Task<T>` | `async throws -> T` |
| `CancellationToken` | кооперативная отмена `Task` |
| `record` | неизменяемая value-модель, близкая к Swift `struct` |
| ASP.NET Identity | готовая подсистема пользователей, паролей и lockout |

## 3. Проекты solution

> Подробный построчный разбор внешнего слоя: [Infrastructure](INFRASTRUCTURE_GUIDE_RU.md).
> Подробный разбор HTTP-слоя: [MoyKabinet.Api](API_GUIDE_RU.md).


Solution находится в `MoyKabinet.Server.slnx` и объединяет пять `.csproj`.

### `MoyKabinet.Domain`

Файл: `src/MoyKabinet.Domain/Entities.cs`.

Содержит чистые сущности:

- `Cabinet` — кабинет и его JSON-состояние, номер ревизии и concurrency token;
- `AccountSession` — серверная сессия устройства;
- `CabinetAccess` — связь аккаунта с кабинетом;
- `CabinetDeviceKey` — отдельный ключ устройства;
- `EmailVerification` — код подтверждения или восстановления;
- `ExternalCredential` — защищённый refresh token внешнего провайдера;
- `BookingReceipt` — результат публичной записи для идемпотентности.

Этот проект не подключает EF Core или ASP.NET. Поэтому предметные сущности не зависят от способа хранения и транспорта.

### `MoyKabinet.Application`

Файл: `src/MoyKabinet.Application/Contracts.cs`.

Здесь находятся:

- request/response DTO: `RegisterRequest`, `LoginRequest`, `AuthSessionDto`;
- интерфейсы: `IAuthService`, `IAccountMailer`, `ISecretGenerator`, `IExternalIdentityVerifier`;
- `AppProblem` — ожидаемая ошибка приложения с HTTP-статусом.

Смысл интерфейса: верхние слои зависят от абстракции, а реализацию можно заменить. Например, production использует SMTP-mailer, а тест использует `FakeMailer`.

### `MoyKabinet.Infrastructure`

Это технические реализации:

- `Persistence.cs` — `AppUser`, `AppDbContext`, таблицы, индексы, связи и cascade delete;
- `AuthService.cs` — регистрация, подтверждение email, вход, refresh, logout, сброс пароля и удаление аккаунта;
- `ExternalIdentityVerifier.cs` — проверка Apple/Google/Яндекс;
- `AccountMailer.cs` — отправка email через SMTP;
- `Security.cs` — генерация случайных секретов и SHA-256 хеширование;
- `CabinetStateValidator.cs` — проверка JSON кабинета;
- `DependencyInjection.cs` — регистрация зависимостей, Identity, SQLite и Data Protection;
- `Migrations/` — история изменений схемы базы.

### `MoyKabinet.Api`

Это вход в программу и HTTP-слой:

- `Program.cs` — composition root: конфигурация сервисов, middleware, маршрутов и миграций;
- `AuthEndpoints.cs` — `/api/auth/...`;
- `CabinetEndpoints.cs` — кабинеты, синхронизация и публичная запись;
- `wwwroot/` — HTML/CSS/JS страницы онлайн-записи;
- `appsettings.json` — несекретная конфигурация.

Используется Minimal API. Это тот же ASP.NET Core, но маршруты объявляются функциями `MapGet`, `MapPost`, `MapPut`, без классов-контроллеров.

### `MoyKabinet.Api.Tests`

Интеграционные xUnit-тесты поднимают сервер в памяти через `WebApplicationFactory`, используют временную SQLite и заменяют настоящий SMTP на `FakeMailer`.

## 4. Как запускается сервер

В `Program.cs` происходят две фазы.

### Регистрация сервисов

`builder.Services` — DI-контейнер. В него регистрируются:

- `AppDbContext` и SQLite;
- ASP.NET Identity;
- `IAuthService → AuthService`;
- SMTP, OAuth verifier, генератор секретов и validator;
- rate limiting и настройки JSON.

`Scoped` создаёт один экземпляр на HTTP-запрос. `Singleton` создаёт один экземпляр на весь процесс сервера.

### HTTP pipeline

После `builder.Build()` запрос проходит по middleware в заданном порядке:

1. forwarded headers от доверенного reverse proxy;
2. HSTS в production;
3. единый exception handler;
4. перенаправление на HTTPS;
5. security headers;
6. rate limiter;
7. static files;
8. подходящий endpoint.

На старте `Database.MigrateAsync()` применяет ещё не применённые EF Core migrations.

## 5. Путь одного запроса

Пример входа:

```http
POST /api/auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "Strong!Pass9",
  "deviceName": "iPhone"
}
```

Путь выполнения:

```text
Kestrel принимает HTTP
 → middleware проверяют ограничения и ошибки
 → endpoint десериализует JSON в LoginRequest
 → DI передаёт реализацию IAuthService
 → AuthService находит AppUser через UserManager
 → SignInManager проверяет хеш пароля и lockout
 → AuthService создаёт access и refresh token
 → в SQLite сохраняются только SHA-256 хеши токенов
 → endpoint сериализует AuthSessionDto в JSON
 → iOS сохраняет выданные токены в Keychain
```

Контроллер/endpoint не должен содержать всю бизнес-логику. Его задача — принять HTTP-данные, вызвать сервис и сформировать ответ.

## 6. Авторизация

### Регистрация по email

1. Сервер проверяет email, пароль и имя.
2. `UserManager` создаёт пользователя и безопасно хеширует пароль.
3. Генерируется шестизначный код.
4. В базе хранится хеш кода, срок 10 минут и число попыток.
5. SMTP отправляет исходный код пользователю.
6. После правильного кода `EmailConfirmed = true`, создаётся сессия.

### Сессия

- access token действует 1 час;
- refresh token действует 90 дней;
- клиент получает исходные токены один раз;
- база хранит только их SHA-256 хеши;
- logout ставит `RevokedAtUtc`;
- refresh отзывает старую сессию и создаёт новую;
- повторное использование старого refresh token возвращает `401`.

Это opaque tokens, а не JWT: токен не содержит claims, сервер ищет его хеш в таблице `Sessions`.

### Защита перебора

ASP.NET Identity считает неудачные входы. После пяти ошибок пользователь блокируется на 15 минут. Для несуществующего email всё равно выполняется дорогое хеширование, чтобы по времени ответа было сложнее определить наличие аккаунта.

### OAuth

Для Google и Яндекса сервер обменивает authorization code, проверяет PKCE, issuer, audience, подпись и срок JWT. Для Apple проверяется identity token. Аккаунт связывается по паре `Provider + ExternalSubject`, а не просто по email.

## 7. База и EF Core

`AppDbContext` описывает наборы таблиц через `DbSet<T>`. `OnModelCreating` задаёт:

- primary и composite keys;
- unique indexes для токенов;
- foreign keys;
- cascade delete;
- concurrency token `Cabinet.Version`.

EF Core преобразует LINQ в SQL. Например:

```csharp
await db.Sessions.SingleOrDefaultAsync(x => x.AccessTokenHash == hash, ct);
```

означает: найти в таблице сессий строку с нужным хешем.

Миграция — версия схемы базы. Она описывает, какие таблицы или столбцы нужно добавить. Это позволяет обновлять production-базу без её удаления.

## 8. Синхронизация кабинета

Кабинет хранит весь iOS snapshot в `StateJson`. Рядом есть `Revision` и `Version`.

При обновлении клиент отправляет известную `revision`. Если сервер уже имеет другую ревизию, он возвращает `409 Conflict`. Если ревизия совпала, сервер валидирует JSON, сохраняет его и увеличивает revision.

Это optimistic concurrency: блокировка заранее не ставится. Сервер предполагает, что конфликт редок, но проверяет его в момент сохранения.

## 9. Публичная запись и идемпотентность

Публичные endpoints позволяют получить профиль, услуги, свободные слоты и создать запись без аккаунта. На них действует отдельный rate limit.

Каждая бронь содержит `RequestID`. Сервер сохраняет `BookingReceipt` с этим ID:

- повтор того же запроса возвращает прежний результат;
- другой запрос с тем же ID возвращает `409`;
- конкурентное занятие слота также возвращает `409`.

Это идемпотентность: повторная отправка из-за плохой сети не создаёт две записи.

## 10. HTTP-статусы проекта

| Код | Значение в проекте |
|---|---|
| `200 OK` | запрос выполнен |
| `201 Created` | кабинет или запись созданы |
| `202 Accepted` | запрос восстановления принят без раскрытия наличия email |
| `400 Bad Request` | неверные входные данные |
| `401 Unauthorized` | нет или истекла сессия/ключ |
| `403 Forbidden` | пользователь известен, но действие пока запрещено |
| `404 Not Found` | ресурс не найден |
| `409 Conflict` | устаревшая ревизия, занятый слот или повтор ID |
| `429 Too Many Requests` | rate limit или блокировка входа |
| `500` | неожиданная внутренняя ошибка без выдачи stack trace клиенту |

## 11. SOLID в этом проекте

- **S — Single Responsibility:** endpoints отвечают за HTTP, `AuthService` за auth-сценарии, mailer за письма, validator за состояние кабинета.
- **O — Open/Closed:** новый mailer или провайдер хранения можно добавить через реализацию интерфейса.
- **L — Liskov Substitution:** `FakeMailer` заменяет `AccountMailer` в тестах и соблюдает тот же контракт.
- **I — Interface Segregation:** интерфейсы небольшие и тематические: mailer не обязан знать про базу или OAuth.
- **D — Dependency Inversion:** API зависит от `IAuthService`, а не создаёт `new AuthService(...)` вручную.

## 12. Что сказать на экзамене за 60 секунд

> Мой backend написан на ASP.NET Core 10 и построен по Clean Architecture. Solution разделён на Domain, Application, Infrastructure и API. Domain содержит сущности и не зависит от ASP.NET или базы. Application содержит DTO и интерфейсы сценариев. Infrastructure реализует их через EF Core, SQLite, ASP.NET Identity, SMTP и OAuth. API использует Minimal API, принимает JSON-запросы и получает сервисы через dependency injection. На старте применяются EF Core migrations. Авторизация использует подтверждение email, lockout и opaque access/refresh tokens, причём в базе лежат только хеши. Синхронизация защищена номером revision и optimistic concurrency, а публичная бронь — request ID для идемпотентности. Поведение проверяется интеграционными xUnit-тестами через реальный HTTP pipeline и временную SQLite.

## 13. Частые вопросы преподавателя

**Почему не MVC-контроллеры?**  
Проект использует Minimal API: для компактного API это уменьшает шаблонный код. Слои, DI, middleware и тестирование остаются такими же.

**Почему сервер — не MVVM?**  
MVVM управляет состоянием UI. У REST backend нет View. Для него подходят endpoints, application services, domain и infrastructure.

**Зачем интерфейсы?**  
Чтобы отделить контракт от реализации, независимо тестировать код и заменять SMTP/OAuth/часы фейками.

**Зачем DTO, если есть entity?**  
Entity отражает внутреннее хранение, DTO — внешний API-контракт. Нельзя случайно отдавать наружу хеш пароля или служебные поля.

**Что делает DI?**  
Контейнер создаёт объект и передаёт его зависимости. Endpoint просит `IAuthService`, а контейнер предоставляет `AuthService` со всеми его зависимостями.

**Что такое middleware?**  
Компонент конвейера, через который проходит каждый запрос до endpoint и ответ после него. Он решает сквозные задачи: ошибки, HTTPS, заголовки и rate limiting.

**Что такое EF Core?**  
ORM: она отображает C#-объекты и LINQ-запросы на таблицы и SQL, отслеживает изменения и выполняет `SaveChangesAsync`.

**Почему SQLite?**  
Она проста в развёртывании и подходит для одного экземпляра небольшого сервиса. При горизонтальном масштабировании стоит перейти на PostgreSQL и вынести фотографии в object storage.

**Где хранится пароль?**  
Исходный пароль не хранится. ASP.NET Identity хранит защищённый salted password hash.

**JWT используется?**  
Для сессии приложения — нет, используются случайные opaque tokens. JWT внешних провайдеров проверяются только при OAuth-входе.

**Чем authentication отличается от authorization?**  
Authentication устанавливает, кто пользователь. Authorization проверяет, имеет ли он право на конкретный кабинет или действие.

**Как обрабатываются ошибки?**  
Ожидаемые ошибки представлены `AppProblem` со статусом. Глобальный exception handler превращает их в безопасный JSON `{ "error": "..." }`; stack trace клиенту не выдаётся.

## 14. Команды для демонстрации

Из папки `Server.AspNetCore`:

```bash
# запуск
dotnet run --no-launch-profile --project src/MoyKabinet.Api

# тесты
dotnet test MoyKabinet.Server.slnx

# production-сборка
dotnet publish src/MoyKabinet.Api/MoyKabinet.Api.csproj -c Release

# применить миграции вручную
dotnet ef database update \
  --project src/MoyKabinet.Infrastructure \
  --startup-project src/MoyKabinet.Api
```

После запуска:

- `GET http://127.0.0.1:8787/health` — проверка процесса;
- `GET http://127.0.0.1:8787/book` — публичная страница;
- `/api/auth/...` — авторизация;
- `/api/cabinets/...` — кабинет и синхронизация;
- `/api/public/...` — публичная онлайн-запись.
