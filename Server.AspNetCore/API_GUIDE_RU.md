# MoyKabinet.Api: подробный разбор HTTP-слоя

## 1. Роль проекта API

`MoyKabinet.Api` — внешний вход в backend. Он находится на границе между сетью и внутренними слоями:

```text
iOS / браузер
      │ HTTP request: method, URL, headers, JSON
      ▼
MoyKabinet.Api
      │ вызывает интерфейсы и DbContext
      ▼
Application + Infrastructure + Domain
      │
      ▼
MoyKabinet.Api
      │ HTTP response: status, headers, JSON
      ▼
iOS / браузер
```

API отвечает за:

- запуск web-сервера;
- конфигурацию HTTP pipeline;
- маршрутизацию;
- преобразование JSON в C# DTO;
- получение зависимостей из DI;
- вызов application/infrastructure logic;
- перевод результата в HTTP status и JSON;
- публичную web-страницу онлайн-записи.

API не должен хешировать пароли или напрямую отправлять SMTP. Для этого он вызывает сервисы Infrastructure.

## 2. Структура папки

```text
MoyKabinet.Api/
├── Program.cs
├── AuthEndpoints.cs
├── CabinetEndpoints.cs
├── appsettings.json
├── appsettings.Development.json
├── Properties/
│   └── launchSettings.json
├── wwwroot/
│   ├── index.html
│   ├── style.css
│   ├── app.js
│   └── favicon.svg
└── MoyKabinet.Api.csproj
```

| Файл | Что делает |
|---|---|
| `Program.cs` | запускает сервер и строит pipeline |
| `AuthEndpoints.cs` | объявляет HTTP API аккаунта |
| `CabinetEndpoints.cs` | кабинет, sync, slots и booking |
| `appsettings.json` | несекретные настройки и пустые placeholders |
| `launchSettings.json` | локальные профили запуска IDE/`dotnet run` |
| `wwwroot` | статический frontend публичной записи |
| `.csproj` | тип проекта, target framework и зависимости |

## 3. `MoyKabinet.Api.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
```

`Sdk.Web` означает исполняемый ASP.NET Core web-проект. Он подключает web-host, Kestrel, конфигурацию и стандартные ASP.NET библиотеки.

```xml
<TargetFramework>net10.0</TargetFramework>
<Nullable>enable</Nullable>
<ImplicitUsings>enable</ImplicitUsings>
```

- `net10.0` — версия платформы;
- nullable reference types заставляют учитывать возможность `null`;
- implicit usings автоматически подключают распространённые namespaces.

Project references:

```text
Api → Domain
Api → Application
Api → Infrastructure
```

API является composition root и поэтому видит все слои: он должен собрать готовое приложение. `Domain` при этом не ссылается обратно на API.

`Microsoft.EntityFrameworkCore.Design` нужен tooling для migrations. `PrivateAssets=all` не даёт design-time package транзитивно утекать потребителям проекта.

## 4. Почему здесь Minimal API

В классическом ASP.NET MVC часто пишут:

```csharp
[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase { ... }
```

В проекте используется Minimal API:

```csharp
app.MapPost("/api/auth/login", ...);
```

Это не отдельный framework. Это компактный синтаксис того же ASP.NET Core.

Плюсы для данного проекта:

- меньше шаблонных классов;
- маршруты видны рядом;
- удобно для небольшого и среднего API;
- DI, middleware, model binding и тестирование остаются полноценными.

## 5. `Program.cs`: точка входа

В файле используются top-level statements. Поэтому явного метода:

```csharp
static void Main(string[] args)
```

нет: компилятор генерирует его автоматически.

`Program.cs` состоит из четырёх частей:

```text
1. Создать builder
2. Зарегистрировать services
3. Построить HTTP pipeline и endpoints
4. Подготовить базу и запустить сервер
```

## 6. Создание `WebApplicationBuilder`

```csharp
var builder = WebApplication.CreateBuilder(
    new WebApplicationOptions
    {
        Args = args,
        WebRootPath = Path.Combine(
            AppContext.BaseDirectory,
            "wwwroot")
    });
```

`builder` содержит:

- DI services;
- configuration;
- logging;
- environment;
- настройки web-host/Kestrel.

`Args = args` передаёт параметры командной строки.

`WebRootPath` явно указывает папку статических файлов относительно опубликованного приложения. Поэтому `/book` и CSS работают, даже если systemd или launchd запустили процесс из другой текущей директории.

## 7. JSON-конфигурация

```csharp
builder.Services.Configure<JsonOptions>(options =>
    options.SerializerOptions.PropertyNamingPolicy =
        JsonNamingPolicy.CamelCase);
```

C#-свойство:

```csharp
AccessToken
```

в JSON становится:

```json
{
  "accessToken": "..."
}
```

Это удобно для Swift `Codable` и JavaScript.

## 8. Регистрация Infrastructure

```csharp
builder.Services.AddInfrastructure(
    builder.Configuration);
```

Эта строка регистрирует:

- `AppDbContext`;
- SQLite;
- Identity;
- `IAuthService`;
- SMTP;
- OAuth verifier;
- Data Protection;
- secret generator;
- cabinet validator.

`Program.cs` не знает, как строится `AuthService` вручную. Этим занимается DI-контейнер.

## 9. Kestrel

Kestrel — встроенный HTTP-сервер ASP.NET Core:

```csharp
builder.WebHost.ConfigureKestrel(options =>
    options.Limits.MaxRequestBodySize = 50_000_000);
```

Общий request body ограничен примерно 50 МБ. Это нужно из-за snapshot кабинета и фотографий, но одновременно защищает сервер от бесконечного body.

Обычно production-схема такая:

```text
Internet
  ▼ HTTPS
Nginx / Caddy / cloud load balancer
  ▼ HTTP внутри private network
Kestrel
  ▼
ASP.NET application
```

## 10. Forwarded headers

Reverse proxy завершает внешний HTTPS и пересылает запрос Kestrel. Без forwarded headers приложение могло бы видеть:

```text
scheme = http
client IP = IP самого proxy
```

```csharp
X-Forwarded-For
X-Forwarded-Proto
```

передают исходный IP и протокол.

Сервер доверяет forwarded headers только от `KnownProxies`, заданных в конфигурации. Это важно: произвольному клиенту нельзя позволять подделывать свой IP заголовком.

`ForwardLimit = 1` разрешает учитывать один proxy hop.

## 11. Rate limiting

Сервер объявляет две политики.

### `auth`: Sliding Window

```text
20 запросов в минуту на IP
4 сегмента окна
очередь отсутствует
```

Окно разбивается на части, поэтому лимит плавнее, чем простой сброс счётчика ровно раз в минуту.

В Testing лимит повышается до 1000, чтобы интеграционные тесты не мешали друг другу.

### `public`: Token Bucket

```text
ёмкость ведра:        60 tokens
пополнение:           20 tokens в минуту
стоимость запроса:    1 token
```

Короткий всплеск разрешается, но длительный поток ограничивается скоростью пополнения.

Если лимит исчерпан:

```http
HTTP 429 Too Many Requests
```

Ключ partition — IP клиента.

## 12. `builder.Build()`

До `Build()` регистрируются зависимости и options.

```csharp
var app = builder.Build();
```

После этого создаётся готовый `WebApplication`, и на нём строится middleware pipeline.

Хорошая формула для экзамена:

```text
builder.Services = что существует в приложении
app.Use...       = через что проходит запрос
app.Map...       = кто обрабатывает конкретный URL
```

## 13. Middleware pipeline

Порядок middleware важен. Запрос движется сверху вниз, ответ возвращается снизу вверх.

```text
Request
  ↓ ForwardedHeaders
  ↓ HSTS
  ↓ ExceptionHandler
  ↓ HTTPS redirection
  ↓ Security headers
  ↓ RateLimiter
  ↓ StaticFiles
  ↓ Endpoint
Response
  ↑ обратно через pipeline
```

### `UseForwardedHeaders`

Восстанавливает исходные scheme и IP после trusted reverse proxy.

### `UseHsts`

В production сообщает браузеру использовать HTTPS. В Development и Testing отключён, чтобы не мешать localhost и тестам.

### `UseExceptionHandler`

Любая необработанная ошибка endpoint попадает сюда:

```csharp
var problem = exception as AppProblem;
context.Response.StatusCode = problem?.Status ?? 500;
```

Если это ожидаемый `AppProblem`, клиент получает заданный статус и безопасное сообщение.

Если это неизвестная ошибка:

```json
{
  "error": "Внутренняя ошибка сервера."
}
```

Stack trace, SQL и секреты наружу не отправляются.

### `UseHttpsRedirection`

Перенаправляет HTTP на HTTPS, когда HTTPS endpoint известен.

### Собственный middleware заголовков

```csharp
app.Use(async (context, next) =>
{
    context.Response.Headers[...] = ...;
    await next();
});
```

`await next()` передаёт управление следующему middleware.

Заголовки:

- `X-Content-Type-Options: nosniff` запрещает браузеру угадывать другой MIME type;
- `Referrer-Policy: same-origin` ограничивает передачу адреса страницы;
- `Content-Security-Policy` разрешает ресурсы только с текущего origin и запрещает встраивание во frame.

### `UseRateLimiter`

Активирует политики, назначенные endpoint через `RequireRateLimiting`.

### `UseDefaultFiles` и `UseStaticFiles`

`UseDefaultFiles` ищет стандартный `index.html` для запроса к директории. `UseStaticFiles` отдаёт HTML, CSS, JS и favicon из `wwwroot`.

## 14. Системные endpoints

```csharp
app.MapGet("/health", () =>
    Results.Ok(new { ok = true }));
```

Используется health check процесса:

```http
GET /health
```

```json
{"ok":true}
```

Он показывает, что приложение отвечает. Это простой liveness endpoint, а не глубокая проверка SMTP/OAuth.

```csharp
app.MapGet("/book", ...);
```

возвращает `wwwroot/index.html` как `text/html`.

## 15. Подключение групп endpoints

```csharp
app.MapAuthEndpoints();
app.MapCabinetEndpoints();
```

Это extension methods из отдельных файлов. Такой подход оставляет `Program.cs` коротким и группирует маршруты по feature.

## 16. Применение миграций

```csharp
await using var scope =
    app.Services.CreateAsyncScope();
```

Почему нужен scope: `AppDbContext` зарегистрирован как scoped. Для startup-кода нет обычного HTTP scope, поэтому он создаётся вручную.

Затем:

1. получается connection string;
2. создаётся каталог SQLite;
3. вызывается `MigrateAsync()`.

EF применяет отсутствующие миграции.

## 17. `app.Run()` и `partial Program`

```csharp
app.Run();
```

Запускает Kestrel и удерживает процесс, пока приложение не остановят.

```csharp
public partial class Program;
```

Компилятор уже создал внутренний `Program` из top-level statements. Эта строка делает тип публично доступным и partial, чтобы тесты могли написать:

```csharp
WebApplicationFactory<Program>
```

Без доступного `Program` интеграционный test host не смог бы найти entry point.

## 18. Как Minimal API получает параметры

Рассмотрим метод:

```csharp
private static async Task<IResult> SlotsAsync(
    string id,
    string service,
    string date,
    AppDbContext db,
    CancellationToken ct)
```

ASP.NET самостоятельно понимает источники:

| Параметр | Источник |
|---|---|
| `id` | route `{id}` |
| `service` | query string `?service=...` |
| `date` | query string `&date=...` |
| `AppDbContext db` | DI-контейнер |
| `CancellationToken ct` | отмена текущего HTTP-запроса |

Для сложного request record:

```csharp
BookingRequest request
```

данные берутся из JSON body.

Для:

```csharp
HttpContext context
```

ASP.NET передаёт текущий HTTP context с headers, request и response.

Это называется parameter binding или model binding.

## 19. `IResult` и `Results`

Endpoint возвращает `IResult`:

```csharp
Results.Ok(data)             // 200
Results.Created(url, data)   // 201
Results.Accepted()           // 202
Results.File(...)            // файл
```

Анонимный C# объект автоматически сериализуется в JSON:

```csharp
Results.Ok(new { deleted = true })
```

превращается в:

```json
{"deleted":true}
```

Ошибки в проекте обычно не возвращаются вручную. Endpoint выбрасывает:

```csharp
throw new AppProblem(409, "...");
```

а глобальный exception handler создаёт ответ.

## 20. `AuthEndpoints.cs`

Все маршруты объединяются prefix-группой:

```csharp
var group = app.MapGroup("/api/auth");
```

Поэтому:

```csharp
group.MapPost("/login", ...)
```

становится:

```text
POST /api/auth/login
```

На группу добавлен лимит body 16 384 байта. Для credentials и OAuth-кодов огромный request не нужен.

### Таблица auth endpoints

| Метод и путь | Назначение | Auth |
|---|---|---|
| `GET /api/auth/config` | доступность способов входа | нет |
| `POST /api/auth/register` | регистрация email | нет, rate limited |
| `POST /api/auth/confirm` | подтверждение кода | нет, rate limited |
| `POST /api/auth/login` | вход | нет, rate limited |
| `POST /api/auth/refresh` | ротация refresh token | refresh token в body |
| `POST /api/auth/password/reset/request` | запрос кода восстановления | нет, rate limited |
| `POST /api/auth/password/reset/confirm` | смена пароля | code в body |
| `POST /api/auth/exchange` | Google/Яндекс code exchange | OAuth proof |
| `POST /api/auth/apple` | Apple sign-in | Apple proof |
| `GET /api/auth/me` | текущий пользователь | access token |
| `POST /api/auth/logout` | отозвать сессию | access token |
| `DELETE /api/auth/me` | удалить аккаунт | access token |

### Пример endpoint

```csharp
group.MapPost("/login", async (
    LoginRequest request,
    IAuthService auth,
    CancellationToken ct) =>
        Results.Ok(await auth.LoginAsync(request, ct)));
```

ASP.NET:

1. читает JSON;
2. создаёт `LoginRequest`;
3. получает `IAuthService` из DI;
4. передаёт request cancellation token;
5. ждёт сервис;
6. сериализует DTO в JSON 200.

Endpoint является тонким: правила пароля, lockout и токены находятся в `AuthService`.

### `/config`

Этот endpoint сообщает iOS, какие кнопки показывать:

```json
{
  "email": true,
  "apple": false,
  "google": false,
  "yandex": false
}
```

OAuth method становится доступным только при полной серверной конфигурации.

## 21. `CabinetEndpoints.cs`: три зоны доступа

В этом файле маршруты логически делятся на три группы.

### Аккаунт пользователя

Использует account access token:

```text
POST /api/cabinets
POST /api/auth/cabinets/link
GET  /api/auth/cabinets
POST /api/auth/cabinets/{id}/key
```

### Синхронизация конкретного кабинета

Использует owner/device key кабинета:

```text
GET    /api/cabinets/{id}/state
PUT    /api/cabinets/{id}/state
DELETE /api/cabinets/{id}
```

### Публичная онлайн-запись

Не требует аккаунта, но rate limited:

```text
GET  /api/public/{id}
GET  /api/public/{id}/slots
POST /api/public/{id}/book
```

Это два разных уровня credentials:

```text
account access token
    подтверждает личность пользователя

cabinet owner/device key
    даёт доступ к данным конкретного кабинета
```

## 22. Создание кабинета

```text
POST /api/cabinets
```

Последовательность:

1. `RequireUserAsync` проверяет account access token;
2. validator проверяет snapshot;
3. secret generator создаёт owner key;
4. в базе сохраняется только hash owner key;
5. создаётся `CabinetAccess` пользователь → кабинет;
6. транзакция `SaveChangesAsync` сохраняет обе сущности;
7. исходный owner key один раз возвращается клиенту.

Ответ `201 Created` содержит `Location` на state resource.

## 23. Чтение, обновление и удаление state

`RequireOwner` читает:

```http
Authorization: Bearer <owner-or-device-key>
```

Доступ разрешён, если совпал:

- основной owner key;
- один из `CabinetDeviceKeys`.

### Update

Клиент отправляет:

```json
{
  "state": { ... },
  "revision": 4
}
```

Сервер проверяет:

```csharp
request.Revision == cabinet.Revision
```

Затем:

```text
валидирует state
заменяет StateJson
revision++
Version = новый Guid
UpdatedAtUtc = now
SaveChangesAsync
```

Два уровня optimistic concurrency:

1. явная `Revision` для протокола iOS;
2. EF `Version` concurrency token для конкурентных SQL updates.

При конфликте возвращается `409`.

## 24. Связь кабинета с аккаунтом

`LinkCabinetAsync` требует одновременно:

- account access token, чтобы знать пользователя;
- owner key, чтобы доказать владение кабинетом.

Затем создаёт связь `CabinetAccess`, если её ещё нет.

`ListCabinetsAsync` выполняет LINQ join между `CabinetAccesses` и `Cabinets` и возвращает короткие `CabinetDto`, а не полный snapshot.

`IssueDeviceKeyAsync` разрешает привязанному аккаунту создать новый ключ устройства. Лимит — 50 ключей на кабинет.

## 25. Публичный профиль

```text
GET /api/public/{id}
```

Сервер возвращает только публичные данные:

- имя мастера;
- специальность;
- timezone;
- неархивные услуги;
- длительность и цену.

Список клиентов, телефоны, notes и appointments наружу не возвращаются.

## 26. Вычисление слотов

Запрос:

```text
GET /api/public/{id}/slots
    ?service=<uuid>
    &date=2026-09-25
```

`BuildSlots`:

1. загружает timezone мастера;
2. разрешает даты от сегодня до +60 дней;
3. проверяет рабочий weekday;
4. берёт opening/closing hour;
5. получает занятые неотменённые записи;
6. идёт по дню шагом 15 минут;
7. проверяет, помещается ли услуга до закрытия;
8. исключает прошлое и ближайший час;
9. исключает пересечения;
10. возвращает свободные интервалы.

Проверка пересечения:

```text
newStart < existingEnd
AND
newEnd > existingStart
```

Поэтому соседние записи допустимы, а пересекающиеся — нет.

## 27. Почему есть `AppleEpoch`

Swift `Date.timeIntervalSinceReferenceDate` считает секунды от:

```text
1 января 2001 года
```

Unix time считает от:

```text
1 января 1970 года
```

Разница:

```csharp
978_307_200 секунд
```

Поэтому сервер добавляет `AppleEpoch`, чтобы получить Unix timestamp и `DateTimeOffset`.

## 28. Создание публичной брони

`BookAsync` выполняет:

1. проверку consent, имени и телефона;
2. проверку UUID request ID;
3. поиск существующего `BookingReceipt`;
4. поиск услуги;
5. преобразование времени iOS;
6. повторную проверку доступности слота на сервере;
7. создание клиента и appointment;
8. полную валидацию нового snapshot;
9. увеличение revision/version;
10. сохранение receipt и state одним `SaveChangesAsync`.

Нельзя доверять тому, что браузер до этого видел свободный слот. Между загрузкой слотов и нажатием кнопки его мог занять другой клиент. Поэтому доступность проверяется повторно во время `POST /book`.

## 29. Идемпотентность booking

Браузер генерирует:

```javascript
requestID ||= crypto.randomUUID();
```

После сетевой ошибки он повторяет запрос с тем же ID.

Сервер сохраняет:

```text
CabinetId
RequestId
RequestHash
ResponseJson
```

Варианты:

```text
ID новый
 → создать запись → 201

тот же ID + те же данные
 → вернуть сохранённый результат → 200

тот же ID + другие данные
 → 409 Conflict
```

Composite primary key не позволяет физически создать два receipt с одной парой `CabinetId + RequestId`.

## 30. `JsonDocument` и `JsonNode`

`JsonDocument/JsonElement` используются для быстрого read-only чтения:

```csharp
using var state = JsonDocument.Parse(...);
```

`JsonDocument` владеет буфером, поэтому освобождается через `using`.

`JsonNode/JsonObject/JsonArray` используются, когда JSON нужно изменить:

```csharp
root["clients"].AsArray().Add(...);
```

`RootElement.Clone()` создаёт независимую копию элемента, которая переживёт disposal исходного `JsonDocument`.

## 31. Private request records

В конце `CabinetEndpoints` объявлены:

```csharp
CreateCabinetRequest
UpdateCabinetRequest
LinkCabinetRequest
BookingRequest
Slot
```

`record` удобен для DTO:

- короткая декларация;
- value-like equality;
- init-only значения;
- автоматическая JSON binding.

Они private, потому что используются только внутри данного endpoint-файла. Общие auth DTO лежат в Application, потому что участвуют в контрактах `IAuthService`.

## 32. Source-generated Regex

```csharp
[GeneratedRegex("...")]
private static partial Regex CabinetIdRegex();
```

Компилятор генерирует оптимизированную реализацию regex во время сборки. Не нужно парсить pattern заново во время каждого запроса.

Проверяются:

- cabinet ID: 32 lowercase hex symbols;
- телефон: допустимые символы и длина.

Для телефона дополнительно считается минимум семь цифр, потому что строка из одних дефисов формально могла бы пройти простую regex.

## 33. Публичный frontend в `wwwroot`

`index.html` содержит форму, `style.css` — pink UI, `app.js` — клиентскую логику.

URL выглядит так:

```text
https://domain/book?cabinet=<cabinet-id>
```

JavaScript:

1. извлекает `cabinet` из query;
2. вызывает публичный profile endpoint;
3. показывает услуги;
4. запрашивает slots;
5. валидирует телефон;
6. создаёт request ID;
7. отправляет booking;
8. показывает подтверждение;
9. может сформировать `.ics` файл календаря.

Frontend повторяет часть простой валидации ради UX, но сервер обязательно проверяет данные заново. Проверка только в JavaScript не является защитой: клиент может вызвать API вручную.

## 34. Конфигурационные файлы

### `appsettings.json`

Содержит defaults:

- SQLite path;
- logging levels;
- Data Protection path;
- known proxies;
- пустые OAuth/SMTP настройки.

Секреты намеренно пустые. В production они приходят через environment variables или secret manager.

ASP.NET объединяет конфигурацию примерно так:

```text
appsettings.json
 → appsettings.{Environment}.json
 → environment variables
 → command-line arguments
```

Более поздний источник переопределяет ранний.

### `appsettings.Development.json`

Содержит локальный logging override.

### `launchSettings.json`

Используется локальными инструментами и IDE. Он задаёт:

- HTTP/HTTPS ports;
- `ASPNETCORE_ENVIRONMENT=Development`;
- автоматическое открытие браузера.

После publish этот файл не является production-конфигурацией сервера.

## 35. Связь API с iOS

```text
iOS AccountAPI
  ↔ /api/auth/*

iOS OnlineAPIClient
  ↔ /api/cabinets/*
  ↔ /api/auth/cabinets/*

Browser booking page
  ↔ /api/public/*
```

JSON camelCase совпадает с DTO iOS. Dates в snapshot используют Apple reference timestamp, поэтому сервер выполняет преобразование при публичной брони.

## 36. Что преподаватель может спросить

**Почему API ссылается на Infrastructure?**  
API является composition root: именно здесь собирается готовое приложение и подключается реализация `AddInfrastructure`. Внутренние слои на API не ссылаются.

**Почему endpoint получает DbContext напрямую?**  
Для компактных CRUD/sync операций Minimal API использует scoped DbContext непосредственно. Более сложные сценарии auth вынесены в `IAuthService`. При росте продукта cabinet use cases можно аналогично вынести в Application handlers.

**Почему не использовать controller?**  
Minimal API уменьшает boilerplate; middleware, model binding, DI и тестируемость остаются теми же.

**Где выполняется авторизация?**  
Account access token проверяет `IAuthService.RequireUserAsync`. Owner/device key проверяет `RequireOwner`. Public endpoints не требуют credentials, но ограничены rate limiter и серверной валидацией.

**Почему два вида токенов?**  
Account token подтверждает пользователя. Cabinet key предоставляет доступ к конкретному синхронизируемому кабинету и может выдаваться отдельным устройствам.

**Что такое `CancellationToken`?**  
Сигнал отмены запроса. Если клиент отключился, операции EF/HTTP/SMTP могут прекратить ненужную работу.

**Почему `async` везде?**  
База и сеть — I/O. Во время ожидания thread освобождается и может обслуживать другой запрос.

**Почему endpoint не ловит каждую ошибку?**  
Ошибки централизованно обрабатывает exception middleware. Это обеспечивает единый формат и не дублирует `try/catch`.

**Что будет при двух одновременных бронях?**  
Обе повторно проверят слот, но concurrency token/unique receipt и `SaveChangesAsync` позволят только согласованное сохранение; проигравший запрос получит `409`.

## 37. Готовый ответ про папку API

> Папка API — presentation/transport layer backend. `Program.cs` является composition root: создаёт WebApplication, регистрирует Infrastructure, Kestrel, forwarded headers и rate limiting, затем строит middleware pipeline и применяет миграции. Проект использует Minimal API. `AuthEndpoints` принимает DTO и делегирует сценарии интерфейсам авторизации. `CabinetEndpoints` обслуживает кабинет, optimistic sync и публичную запись. ASP.NET model binding получает route, query, JSON body, HttpContext, CancellationToken и DI-сервисы из параметров endpoint. Результаты возвращаются через `IResult`, а `AppProblem` централизованно преобразуется exception middleware в безопасный JSON. `wwwroot` содержит статическую страницу, которая использует только публичные rate-limited endpoints.
