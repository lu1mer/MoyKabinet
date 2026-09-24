# Security policy

## Сообщить об уязвимости

Не публикуйте сведения об уязвимости, токены, ключи или персональные данные в открытом issue. Используйте **Security → Report a vulnerability** в GitHub-репозитории либо свяжитесь с владельцем репозитория приватно.

В сообщении укажите затронутую версию, шаги воспроизведения, возможное влияние и минимальный пример запроса. Не проверяйте уязвимость на чужих аккаунтах и реальных данных.

## Секреты и данные

- OAuth client secrets, Apple `.p8`, SMTP-пароли и production-конфигурация передаются только через secret manager или переменные окружения.
- Файлы базы SQLite, Data Protection keys, `.env`, сертификаты и signing profiles не должны попадать в Git.
- При случайной публикации секрета его нужно немедленно отозвать у провайдера; удаления из истории Git недостаточно.
- Production-сервер запускается только за HTTPS reverse proxy. Каталог `/data` должен быть закрыт от других пользователей, зашифрован на уровне диска и регулярно резервироваться.

Перед релизом запустите:

```sh
dotnet test Server.AspNetCore/MoyKabinet.Server.slnx
dotnet list Server.AspNetCore/MoyKabinet.Server.slnx package --vulnerable --include-transitive
```
