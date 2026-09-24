# Регистрация и вход: email, Apple, Google и Яндекс

Экран входа открывается после анимации запуска и не пропускает нового пользователя без аккаунта. Email-регистрация требует шестизначный код из письма; есть восстановление пароля. Первый успешный вход через Apple, Google или Яндекс создаёт аккаунт по неизменному идентификатору провайдера. Совпадение email у разных провайдеров не объединяет аккаунты автоматически. Сессия хранится в Keychain. После первого входа загруженное расписание остаётся доступным офлайн.

Для реального входа нужны собственный HTTPS-сервер, SMTP и зарегистрированные OAuth-приложения. Секреты хранятся только на сервере. При отсутствии настроек соответствующий способ входа отключён; успешный вход не имитируется.

## 1. ASP.NET Core сервер

Разместите `Server.AspNetCore` за HTTPS и задайте переменные окружения:

| Способ | Переменные сервера |
|---|---|
| Email | `Email__SmtpHost`, `Email__SmtpPort`, `Email__UseTls`, `Email__Username`, `Email__Password`, `Email__From` |
| Google | `Auth__Google__ClientId`, `Auth__Google__RedirectUris`; `Auth__Google__ClientSecret` при необходимости |
| Яндекс | `Auth__Yandex__ClientId`, `Auth__Yandex__RedirectUris`; `Auth__Yandex__ClientSecret` при необходимости |
| Apple | `Auth__Apple__ClientId`, `Auth__Apple__TeamId`, `Auth__Apple__KeyId`, `Auth__Apple__PrivateKey` |

Пример URI Яндекса: `moykabinet://oauth/yandex`. URI Google для Client ID `123-abc.apps.googleusercontent.com`: `com.googleusercontent.apps.123-abc:/oauth/google`. Списки `RedirectUris` разделяются запятыми и должны точно совпадать с настройками провайдеров и iOS. В Production без рабочего SMTP регистрация по email завершается ошибкой; код никогда не возвращается клиенту. В Development он печатается только в локальный серверный лог.

Access token действует час, rotating refresh token — 90 дней; сервер хранит только SHA-256 хеши. После пяти неверных паролей вход блокируется на 15 минут. Apple refresh token защищается ASP.NET Data Protection и отзывается перед удалением аккаунта. Полная конфигурация сервера описана в [Server.AspNetCore/README.md](Server.AspNetCore/README.md).

## 2. Регистрация приложений у провайдеров

- **Apple:** включите Sign in with Apple для App ID приложения, создайте ключ и передайте содержимое `.p8` в секрет `Auth__Apple__PrivateKey`. `Auth__Apple__ClientId` должен совпадать с Bundle ID подписанного приложения.
- **Google:** создайте OAuth client типа iOS с тем же Bundle ID. Укажите его Client ID в сервере и Xcode. Зарегистрируйте обратную URL-схему этого ID в приложении; `project.yml` поддерживает настройку схемы через `AUTH_GOOGLE_REDIRECT_SCHEME`.
- **Яндекс:** создайте приложение для входа через Яндекс ID, разрешите `login:info` и `login:email`, добавьте `moykabinet://oauth/yandex` в Redirect URI. Client ID должен совпадать на сервере и в Xcode.

Параметры потока сверены с [Google OAuth для iOS](https://developers.google.com/identity/protocols/oauth2/native-app), [Яндекс OAuth с PKCE](https://yandex.ru/dev/id/doc/ru/codes/code-url) и [Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple).

## 3. Конфигурация iOS

В настройках сборки Xcode задайте `AUTH_SERVER_URL`, `AUTH_GOOGLE_CLIENT_ID`, `AUTH_GOOGLE_REDIRECT_SCHEME` и `AUTH_YANDEX_CLIENT_ID`. Адрес сервера должен быть HTTPS; HTTP допустим только для локального теста на `localhost`/`127.0.0.1`. В `project.yml`/`Info.plist` уже есть схема возврата Яндекса; схема Google подставляется из настройки сборки. При смене Bundle ID обновите Apple Client ID на сервере и включите capability для нового App ID.

## 4. Связь аккаунта с кабинетом

После входа откройте «Кабинет → Онлайн-запись» и включите онлайн-кабинет на том же сервере. Новый кабинет сразу связывается с текущим аккаунтом. На другом iPhone войдите тем же способом, выберите кабинет из списка и подключите его. Если на втором устройстве уже есть локальные записи, сначала экспортируйте резервную копию и очистите локальный кабинет — приложение не затирает существующие данные автоматически.

При доступном сервере выход отзывает сессию сервиса; локальная сессия удаляется с iPhone и при ошибке сети. Выход не удаляет данные кабинета; отключение и удаление онлайн-кабинета находятся отдельно в настройках онлайн-записи.

Удалить аккаунт можно на экране «Аккаунт → Удалить аккаунт». После подтверждения сервер удаляет профиль, сессии и связи аккаунта с онлайн-кабинетами; локальные записи и сам онлайн-кабинет остаются отдельно, чтобы не удалить расписание другого устройства. Онлайн-кабинет можно удалить в настройках онлайн-записи.
