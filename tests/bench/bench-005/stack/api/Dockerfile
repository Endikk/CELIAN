# BENCH-005 test API. Base images pinned by digest (read on 2026-11-19):
# SDK 10.0.404 and runtime 10.0.15, the patch release of 2026-11-10.
FROM mcr.microsoft.com/dotnet/sdk:10.0.404@sha256:bef136a371963aaa46ec97882845ef6f54dec15728bb4b128b1c2a400ffbc9b4 AS build
WORKDIR /src
COPY Api.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0.15@sha256:12b1135f5f8b3c0a214f2a680ff2033dff4f684f445d6c697d9524ceeb303586
WORKDIR /app
COPY --from=build /app .
USER $APP_UID
ENTRYPOINT ["dotnet", "Api.dll"]
