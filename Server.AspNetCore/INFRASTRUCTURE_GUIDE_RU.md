# Infrastructure в «Мой кабинет»: подробный разбор

## 1. Зачем вообще нужен Infrastructure

`Infrastructure` — внешний технический слой Clean Architecture. Он отвечает не за смысл продукта, а за способы выполнения работы:

- где физически хранить данные;
- как хешировать пароль и токены;
- как отправить письмо;
- как обратиться к Apple, Google или Яндексу;
- как зашифровать внешний refresh token;
- как зарегистрировать реализации в Dependency Injection.

Application объявляет требование:

```csharp
public interface IAccountMailer
{
    Task SendVerificationCodeAsync(...);
}
```

Infrastructure предоставляет конкретную реализацию:

```csharp
public sealed class AccountMailer : IAccountMailer
```

API знает интерфейс и получает реализацию через DI. Благодаря этому тест может заменить SMTP на `FakeMailer`, не меняя `AuthService` и endpoints.

```text
Application: «мне нужен объект, умеющий отправить код»
                         ▲
                         │ implements
Infrastructure: «я отправлю его через SMTP»
```

Infrastructure зависит от `Application` и `Domain`. Обратной зависимости нет: `Domain` не знает ни про EF Core, ни про SMTP.

## 2. Содержимое папки

```text
MoyKabinet.Infrastructure/
├── DependencyInjection.cs
├── Persistence.cs
├── AuthService.cs
├── Security.cs
├── AccountMailer.cs
├── ExternalIdentityVerifier.cs
├── CabinetStateValidator.cs
├── Migrations/
└── MoyKabinet.Infrastructure.csproj
```

| Файл | Ответственность |
|---|---|
| `DependencyInjection.cs` | собирает технические зависимости |
| `Persistence.cs` | описывает пользователя, DbContext, таблицы и связи |
| `AuthService.cs` | реализует сценарии аккаунта и серверных сессий |
| `Security.cs` | создаёт случайные секреты, хеширует и сравнивает их |
| `AccountMailer.cs` | отправляет коды через SMTP |
| `ExternalIdentityVerifier.cs` | проверяет Apple/Google/Яндекс OAuth |
| `CabinetStateValidator.cs` | проверяет входящий JSON кабинета |
| `Migrations/` | версионирует физическую схему SQLite |

## 3. `DependencyInjection.cs`: composition вспомогательного слоя

Главный метод:

```csharp
public static IServiceCollection AddInfrastructure(
    this IServiceCollection services,
    IConfiguration configuration)
```

Это extension method для `IServiceCollection`. В `Program.cs` достаточно вызвать:

```csharp
builder.Services.AddInfrastructure(builder.Configuration);
```

После этого DI-контейнер знает, как создавать все инфраструктурные объекты.

### Подключение SQLite

```csharp
var connection = configuration.GetConnectionString("Database")
    ?? "Data Source=data/moykabinet.db";

services.AddDbContext<AppDbContext>(options =>
    options.UseSqlite(connection));
```

`AddDbContext` регистрирует `AppDbContext` со временем жизни `Scoped`. Для каждого HTTP-запроса создаётся свой context. Это правильно, потому что `DbContext` отслеживает изменения и не является thread-safe.

В production connection string приходит из переменной:

```text
ConnectionStrings__Database=Data Source=/data/moykabinet.db
```

ASP.NET преобразует двойное подчёркивание в разделитель конфигурации `:`.

### Настройка ASP.NET Identity

```csharp
services.AddIdentityCore<AppUser>(options => { ... })
```

Identity предоставляет:

- `UserManager<AppUser>` для создания и изменения пользователей;
- `SignInManager<AppUser>` для проверки пароля и lockout;
- `PasswordHasher`;
- таблицы пользователей;
- генераторы токенов сброса пароля.

Настройки проекта:

```text
уникальный email              да
минимальная длина пароля      10
цифра                         обязательна
строчная буква                обязательна
заглавная буква               обязательна
спецсимвол                    обязателен
блокировка                    после 5 ошибок
срок блокировки               15 минут
```

Цепочка:

```csharp
.AddSignInManager()
.AddEntityFrameworkStores<AppDbContext>()
.AddDefaultTokenProviders();
```

означает:

1. зарегистрировать `SignInManager`;
2. хранить Identity-пользователей через наш `AppDbContext`;
3. добавить стандартные генераторы служебных токенов Identity.

### Именованный `HttpClient`

```csharp
services.AddHttpClient("oauth", client =>
    client.Timeout = TimeSpan.FromSeconds(15));
```

`IHttpClientFactory` управляет HTTP-клиентами для OAuth. Это лучше, чем постоянно создавать `new HttpClient()`: фабрика правильно переиспользует сетевые handlers и снижает риск socket exhaustion.

```csharp
AllowAutoRedirect = false
```

Отключает автоматические redirect от внешнего сервера. OAuth verifier должен получить ожидаемый ответ, а не незаметно уйти на произвольный адрес.

### ASP.NET Data Protection

```csharp
services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(keys))
    .SetApplicationName("MoyKabinet");
```

Data Protection шифрует Apple refresh token перед записью в базу. Ключи лежат отдельно в `data/keys`.

Почему каталог ключей нужно резервировать: если потерять его, сохранённый refresh token уже нельзя расшифровать и отозвать у Apple.

### Lifetime зависимостей

```csharp
AddSingleton<IClock, SystemClock>();
AddSingleton<ISecretGenerator, SecretGenerator>();
AddSingleton<ICabinetStateValidator, CabinetStateValidator>();
AddScoped<IAccountMailer, AccountMailer>();
AddScoped<IAuthService, AuthService>();
AddSingleton<IExternalIdentityVerifier, ExternalIdentityVerifier>();
```

- `Singleton` — один экземпляр на весь процесс. Используется для stateless и thread-safe объектов.
- `Scoped` — один экземпляр на HTTP-запрос. `AuthService` scoped, потому что использует scoped `AppDbContext`.
- `Transient` — новый объект при каждом запросе из контейнера; здесь явно не используется.

Важное правило DI: singleton нельзя заставлять напрямую зависеть от scoped-объекта. В текущем проекте singleton verifier использует singleton `IHttpClientFactory` и конфигурацию, поэтому конфликтов lifetime нет.

## 4. `Persistence.cs`: EF Core и Identity

### `AppUser`

```csharp
public sealed class AppUser : IdentityUser
```

`IdentityUser` уже содержит:

- `Id`;
- `UserName` и `NormalizedUserName`;
- `Email` и `NormalizedEmail`;
- `PasswordHash`;
- `EmailConfirmed`;
- `AccessFailedCount`;
- `LockoutEnd`;
- security/concurrency stamp.

Проект добавляет:

```csharp
DisplayName
ProfileEmail
Provider
ExternalSubject
AvatarUrl
```

`Provider` показывает способ создания аккаунта: `email`, `apple`, `google`, `yandex`.

`ExternalSubject` — стабильный ID пользователя у OAuth-провайдера. Для внешнего входа личность определяется парой:

```text
Provider + ExternalSubject
```

Email для этого не используется как главный идентификатор: пользователь может скрыть Apple email или поменять адрес.

### `AppDbContext`

```csharp
public sealed class AppDbContext
    : IdentityDbContext<AppUser>
```

Наследование от `IdentityDbContext` добавляет стандартные Identity-таблицы. Наши `DbSet` добавляют таблицы продукта:

```csharp
DbSet<Cabinet>
DbSet<AccountSession>
DbSet<CabinetAccess>
DbSet<CabinetDeviceKey>
DbSet<EmailVerification>
DbSet<ExternalCredential>
DbSet<BookingReceipt>
```

`DbSet<T>` можно воспринимать как точку построения SQL-запросов к таблице `T`.

### Что делает `OnModelCreating`

`OnModelCreating` настраивает схему базы через Fluent API.

Сначала обязательно вызывается:

```csharp
base.OnModelCreating(builder);
```

Без этого Identity не настроит свои таблицы и ключи.

### Уникальные индексы

```csharp
HasIndex(x => new { x.Provider, x.ExternalSubject }).IsUnique();
```

Запрещает создать два аккаунта для одной внешней личности.

```csharp
HasIndex(x => x.AccessTokenHash).IsUnique();
HasIndex(x => x.RefreshTokenHash).IsUnique();
```

Не позволяет двум сессиям иметь одинаковый токен.

```csharp
HasIndex(x => x.KeyHash).IsUnique();
```

Обеспечивает уникальность ключа устройства.

Индекс — дополнительная структура базы, ускоряющая поиск. Unique index одновременно обеспечивает ограничение целостности.

### Составные первичные ключи

```csharp
CabinetAccess:   UserId + CabinetId
BookingReceipt:  CabinetId + RequestId
```

Первая пара запрещает повторную связь одного аккаунта с одним кабинетом. Вторая гарантирует один receipt на request ID внутри кабинета.

### Foreign key и cascade delete

Пример:

```csharp
AccountSession.UserId → AppUser.Id
```

`OnDelete(DeleteBehavior.Cascade)` означает: при удалении пользователя база автоматически удаляет его сессии, подтверждения, связи и external credential.

```text
AppUser
 ├── AccountSession
 ├── EmailVerification
 ├── CabinetAccess
 └── ExternalCredential
```

При удалении кабинета каскадно удаляются:

```text
Cabinet
 ├── CabinetAccess
 ├── CabinetDeviceKey
 └── BookingReceipt
```

### Concurrency token

```csharp
builder.Entity<Cabinet>()
    .Property(x => x.Version)
    .IsConcurrencyToken();
```

EF запоминает прочитанное значение `Version` и включает его в условие `UPDATE`. Если другая операция уже изменила запись, затронуто ноль строк и EF выбрасывает `DbUpdateConcurrencyException`.

Упрощённый SQL выглядит так:

```sql
UPDATE Cabinets
SET StateJson = ..., Version = ...
WHERE Id = ... AND Version = oldVersion;
```

## 5. `Security.cs`: случайные секреты и хеширование

### `SystemClock`

```csharp
public DateTime UtcNow => DateTime.UtcNow;
```

Почему время скрыто за `IClock`: сервису можно передать fake clock в тесте и проверить истечение кода или токена без реального ожидания.

### Создание токена

```csharp
RandomNumberGenerator.GetBytes(bytes)
```

Используется криптографический генератор, а не обычный `Random`. Обычный генератор предсказуем и не подходит для токенов.

Байты кодируются в Base64URL:

```text
+ заменяется на -
/ заменяется на _
= в конце удаляется
```

Такой токен безопасно передавать в HTTP и JSON.

### Хеш токена

```csharp
SHA256(value) → hex string
```

Клиент получает исходный access/refresh token. Сервер сохраняет только хеш. При запросе сервер снова хеширует присланный токен и ищет совпадение.

Если база утечёт, исходные токены нельзя просто взять и использовать.

### Constant-time comparison

```csharp
CryptographicOperations.FixedTimeEquals(...)
```

Обычное сравнение может закончиться на первом несовпавшем байте. Разница времени теоретически раскрывает информацию. `FixedTimeEquals` сравнивает массивы за примерно одинаковое время.

## 6. `AuthService.cs`: центральная реализация аккаунта

Конструктор получает все зависимости через DI:

```csharp
AppDbContext
UserManager<AppUser>
SignInManager<AppUser>
ISecretGenerator
IClock
IAccountMailer
IExternalIdentityVerifier
IDataProtectionProvider
```

`AuthService` не создаёт их самостоятельно. Это Dependency Inversion и constructor injection.

### Регистрация

`RegisterAsync`:

1. проверяет базовые размеры email и пароля;
2. нормализует email;
3. проверяет уникальность;
4. создаёт `AppUser` через `UserManager`;
5. Identity проверяет политику пароля и сохраняет его хеш;
6. создаёт шестизначный код через `RandomNumberGenerator`;
7. сохраняет SHA-256 хеш кода и срок `+10 минут`;
8. вызывает `IAccountMailer`;
9. если SMTP упал, удаляет созданного пользователя, чтобы не оставить аккаунт, который нельзя подтвердить.

Последний пункт — компенсация: несколько внешних действий нельзя объединить одной транзакцией SQLite+SMTP, поэтому код вручную откатывает пользователя при ошибке письма.

### Подтверждение email

`ConfirmAsync`:

1. находит пользователя и последнюю запись verification;
2. увеличивает число попыток;
3. проверяет срок, лимит 5 и хеш кода;
4. устанавливает `EmailConfirmed = true`;
5. удаляет использованные коды;
6. выдаёт сессию.

Сообщение одинаковое для неверного и истёкшего кода, поэтому наружу не раскрываются лишние детали.

### Вход

```csharp
signIn.CheckPasswordSignInAsync(
    user,
    request.Password,
    lockoutOnFailure: true)
```

Identity:

- хеширует полученный пароль;
- сравнивает его с `PasswordHash`;
- увеличивает `AccessFailedCount` при ошибке;
- устанавливает `LockoutEnd` после пяти ошибок.

Если email не существует, вызывается `PasswordHasherWorkAsync`. Это искусственно выполняет дорогую операцию хеширования, чтобы ответы для существующего и несуществующего email меньше отличались по времени.

### Выдача сессии

`IssueAsync` создаёт:

```text
access token:   32 random bytes, срок 1 час
refresh token:  48 random bytes, срок 90 дней
```

В `Sessions` записываются:

- хеш access token;
- хеш refresh token;
- сроки;
- user ID;
- название устройства;
- состояние отзыва.

Исходные токены возвращаются DTO только клиенту.

### Проверка access token

`RequireSessionAsync`:

1. требует заголовок `Authorization: Bearer ...`;
2. ограничивает его длину;
3. хеширует токен;
4. ищет сессию;
5. проверяет `RevokedAtUtc` и срок;
6. загружает пользователя.

В проекте токены проверяются вручную через `IAuthService`. Поэтому `AddAuthentication()` зарегистрирован, но стандартный JWT Bearer handler и атрибут `[Authorize]` не используются. Это нормальное решение для собственных opaque tokens, и его важно уметь объяснить.

### Refresh rotation

`RefreshAsync` сначала читает сессию, затем атомарно отзывает её через `ExecuteUpdateAsync` с условием `RevokedAtUtc == null`.

Если два запроса одновременно используют один refresh token:

```text
запрос A → обновил 1 строку → получает новую сессию
запрос B → обновил 0 строк → получает 401
```

Так старый refresh token нельзя успешно применить дважды.

### Восстановление пароля

Запрос сброса всегда отвечает одинаково. Если email не существует, выполняется fake hashing и метод завершается. Это защищает от account enumeration.

После правильного кода:

1. Identity создаёт внутренний reset token;
2. меняет password hash;
3. сервер отзывает все активные сессии пользователя;
4. verification codes удаляются.

### Внешний аккаунт

`ExternalAsync` ищет пользователя по `Provider + Subject`. Если его нет — создаёт. Имя, email и avatar обновляются из проверенной информации провайдера.

Apple может выдать refresh token. Он шифруется:

```csharp
credentialProtector.Protect(token)
```

и только затем сохраняется в `ExternalCredentials`.

При удалении аккаунта токен расшифровывается, отправляется запрос отзыва Apple, после чего Identity удаляет пользователя. Cascade delete удаляет связанные локальные записи аккаунта.

## 7. `AccountMailer.cs`: SMTP adapter

`AccountMailer` получает:

- `IConfiguration` — адрес SMTP и credentials;
- `IHostEnvironment` — Development или Production;
- `ILogger` — безопасный серверный лог.

Если SMTP не настроен:

- в Development код выводится в локальный лог;
- в Production возвращается `503`, регистрация не притворяется успешной.

`SmtpClient` создаётся на время отправки и освобождается через `using`. TLS по умолчанию включён, порт по умолчанию — 587.

В конфигурации используются:

```text
Email:SmtpHost
Email:SmtpPort
Email:UseTls
Email:Username
Email:Password
Email:From
```

В environment variables это превращается в `Email__SmtpHost` и так далее.

`CancellationToken` передаётся в `SendMailAsync`: если HTTP-запрос отменён или сервер завершает работу, операция может прекратиться кооперативно.

## 8. `ExternalIdentityVerifier.cs`: OAuth adapter

Этот класс не доверяет данным, просто присланным iPhone. Он сам общается с провайдером и проверяет доказательства входа.

### Общая защита

- ограничиваются размеры code/token;
- PKCE verifier должен быть длиной 43–128 и содержать допустимые символы;
- redirect URI должен точно присутствовать в allowlist;
- HTTP timeout — 15 секунд;
- автоматические redirects отключены;
- JWT проверяется по подписи, issuer, audience и lifetime;
- допустимый clock skew — 2 минуты.

### Google

1. iPhone присылает authorization code, PKCE verifier и redirect URI.
2. Сервер проверяет redirect allowlist.
3. Сервер обменивает code на токены у Google.
4. Из ответа берётся `id_token`.
5. OpenID metadata предоставляет актуальные signing keys.
6. Проверяются подпись, `iss`, `aud`, срок.
7. Из claims берутся `sub`, подтверждённый email, имя и avatar.

Главный ID — claim `sub`, а не email.

### Яндекс

1. code обменивается на access token с PKCE;
2. access token отправляется в Yandex info endpoint;
3. сервер сверяет `client_id`, чтобы токен был выдан именно нашему приложению;
4. берётся стабильный `id`/`psuid`, email и имя.

### Apple

Apple flow проверяется дважды:

1. проверяется identity token, пришедший от iPhone;
2. authorization code обменивается сервером;
3. проверяется второй `id_token` из ответа Apple;
4. `sub` обоих токенов должен совпасть с `UserIdentifier`.

Для обмена сервер создаёт краткоживущий Apple client secret — подписанный ES256 JWT. Для подписи используется `.p8` private key владельца приложения.

Если Apple дал refresh token, он сохраняется зашифрованным. При удалении аккаунта `RevokeAsync` вызывает Apple revoke endpoint.

### Зачем OpenID metadata

Google и Apple публикуют endpoint с issuer, endpoints и публичными signing keys. `ConfigurationManager<OpenIdConnectConfiguration>` получает и кеширует эту информацию. Поэтому ключи ротации не приходится зашивать в код.

## 9. `CabinetStateValidator.cs`: граница недоверенных данных

iOS присылает целый JSON snapshot. Нельзя сразу записывать его в базу, потому что клиент может быть старым, повреждённым или вредоносным.

Validator проверяет:

- корень является object;
- присутствуют массивы clients/services/appointments;
- размер массивов ограничен;
- profile существует;
- рабочие часы корректны;
- ID являются UUID и не повторяются;
- запись ссылается на существующего клиента;
- длины строк ограничены;
- длительность услуги/записи: 15–480 минут;
- цена: 0–1 000 000;
- не более 8 фото на клиента;
- дата конечна и представлена числом;
- глубина JSON ограничена 64.

Это защита целостности и частично защита от resource exhaustion. Дополнительно Kestrel ограничивает размер HTTP body до 50 МБ.

Почему validator stateless singleton: он не хранит request-specific состояние, работает только с аргументом и создаёт новый `JsonDocument`.

## 10. `Migrations`: версия базы

Migration — C#-описание изменения физической схемы.

Первая migration `InitialProduction` создаёт:

- Identity tables;
- `Cabinets`;
- `Sessions`;
- `CabinetAccesses`;
- `CabinetDeviceKeys`;
- `EmailVerifications`;
- `ExternalCredentials`;
- `BookingReceipts`;
- foreign keys и indexes.

Вторая migration `AddVerificationPurpose` добавляет поле `Purpose`, чтобы одной таблицей обслуживать подтверждение email и восстановление пароля.

На старте API вызывает:

```csharp
await db.Database.MigrateAsync();
```

EF смотрит таблицу `__EFMigrationsHistory` и применяет только отсутствующие миграции.

Для production безопаснее запускать migration отдельным deployment job после резервной копии, особенно если запущено несколько экземпляров API.

## 11. Полная цепочка регистрации

```text
AuthEndpoints
    │ RegisterRequest
    ▼
IAuthService
    │ DI выбрал AuthService
    ▼
AuthService
    ├── UserManager<AppUser>
    │      └── AppDbContext → SQLite: AspNetUsers
    ├── SecretGenerator
    │      └── случайный code + SHA-256
    ├── AppDbContext
    │      └── SQLite: EmailVerifications
    └── IAccountMailer
           └── AccountMailer → SMTP
```

Подтверждение:

```text
code от iPhone
 → SecretGenerator.Matches
 → EmailConfirmed = true
 → удалить verification
 → IssueAsync
 → сохранить hashes в Sessions
 → вернуть исходные токены iPhone
```

## 12. Полная цепочка Google-входа

```text
iPhone получает authorization code
 → POST /api/auth/exchange
 → ExternalIdentityVerifier
 → Google token endpoint
 → получить id_token
 → OpenID metadata + signing keys
 → проверить signature/issuer/audience/lifetime
 → ExternalIdentity(provider, sub, email, name)
 → AuthService.ExternalAsync
 → найти или создать AppUser
 → IssueAsync
 → access/refresh token для iPhone
```

## 13. Как Infrastructure тестируется

Интеграционные тесты используют `WebApplicationFactory<Program>`. Она поднимает настоящий ASP.NET pipeline без отдельного внешнего процесса.

В `ApiFactory` DI заменяет зависимости:

```csharp
реальная SQLite production path → временный SQLite-файл
реальный AccountMailer          → FakeMailer
```

`FakeMailer` сохраняет код в словарь. Тест читает его и подтверждает пользователя. Это доказывает пользу интерфейсов и Dependency Inversion.

Тесты проверяют:

- регистрацию и подтверждение;
- refresh rotation и replay rejection;
- logout;
- lockout;
- password reset и отзыв сессий;
- удаление аккаунта;
- сохранение кабинета и stale revision;
- идемпотентную публичную бронь.

## 14. Что важно честно сказать на экзамене

Текущая Infrastructure подходит для MVP и одного экземпляра сервера. Для большой production-нагрузки логичны следующие изменения:

- SQLite заменить на PostgreSQL;
- snapshots кабинета нормализовать в отдельные таблицы или добавить инкрементальный журнал изменений;
- фотографии вынести в S3-compatible object storage;
- отправку email вынести в background queue с transactional outbox;
- добавить централизованные metrics, tracing и structured logs;
- миграции запускать отдельным deployment job;
- добавить distributed rate limiting и Redis при нескольких API instances.

Это не означает, что текущая архитектура неправильная. Абстракции позволяют менять технические adapters, сохраняя Application-контракты и Domain.

## 15. Готовый ответ про Infrastructure

> Infrastructure — внешний слой Clean Architecture, который реализует технические интерфейсы Application. В моём проекте он отвечает за EF Core и SQLite, ASP.NET Identity, собственные opaque-сессии, SMTP, OAuth Apple/Google/Яндекс, Data Protection, криптографические секреты, валидацию JSON и миграции. `AppDbContext` наследуется от `IdentityDbContext<AppUser>` и описывает связи, индексы, cascade delete и concurrency token. `AuthService` реализует `IAuthService`: создаёт пользователя через Identity, подтверждает email, выдаёт access/refresh token, хранит только их хеши и атомарно ротирует refresh token. Конкретные реализации регистрируются в DI через `AddInfrastructure`. Благодаря интерфейсам production SMTP и SQLite можно заменить fake-реализациями в интеграционных тестах.
