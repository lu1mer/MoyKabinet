FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore MoyKabinet.Server.slnx && dotnet publish src/MoyKabinet.Api/MoyKabinet.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
RUN useradd --uid 10001 --create-home appuser
WORKDIR /app
COPY --from=build /app .
RUN mkdir -p /data && chown -R appuser:appuser /data /app
USER appuser
ENV ASPNETCORE_URLS=http://0.0.0.0:8080 \
    ConnectionStrings__Database="Data Source=/data/moykabinet.db" \
    DataProtection__KeysPath=/data/keys
EXPOSE 8080
ENTRYPOINT ["dotnet", "MoyKabinet.Api.dll"]
