# API of the SaaS B2B golden repo (spec 001, step 3). Build context: src/.
# Base images pinned by digest (S01): the builds of 2026-11-18 of SDK 10.0.404
# and ASP.NET Core 10.0.15. Dates and sources: research RS-18 of spec 001.
# Renovate has no publication date for mcr.microsoft.com, so these digests
# move by hand, after their 7 days (research RS-17 and RS-18).
#
# Stages, all run by tests/unit/u01-api.sh except the last two:
# - test: U01 in the build image (research RS-06);
# - openapi-document: openapi.json written from the API (--update-openapi);
# - lock-files: packages.lock.json resolved anew (--update-locks);
# - publish, then runtime: the image of the API.

FROM mcr.microsoft.com/dotnet/sdk:10.0.404@sha256:bef136a371963aaa46ec97882845ef6f54dec15728bb4b128b1c2a400ffbc9b4 AS sdk
WORKDIR /src
COPY nuget.config Directory.Build.props ./
# No usage data sent to Microsoft by the SDK nor by the test platform (research
# RS-18).
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=true

FROM sdk AS lock
COPY Api/Api.csproj Api/
COPY Api.Tests/Api.Tests.csproj Api.Tests/
RUN dotnet restore Api.Tests/Api.Tests.csproj

FROM scratch AS lock-files
COPY --from=lock /src/Api/packages.lock.json /Api/
COPY --from=lock /src/Api.Tests/packages.lock.json /Api.Tests/

# Locked mode: restore fails if a project asks for a package graph other than
# the one its packages.lock.json holds (research RS-18).
FROM sdk AS build
COPY Api/Api.csproj Api/packages.lock.json Api/
COPY Api.Tests/Api.Tests.csproj Api.Tests/packages.lock.json Api.Tests/
RUN dotnet restore Api.Tests/Api.Tests.csproj --locked-mode
COPY . .
RUN dotnet build Api.Tests/Api.Tests.csproj --configuration Release --no-restore

FROM build AS test
RUN dotnet run --project Api.Tests/Api.Tests.csproj --configuration Release --no-build

FROM build AS openapi
RUN mkdir /out \
    && OPENAPI_DOCUMENT_OUTPUT=/out/openapi.json \
       dotnet run --project Api.Tests/Api.Tests.csproj --configuration Release --no-build

FROM scratch AS openapi-document
COPY --from=openapi /out/openapi.json /

FROM build AS publish
RUN dotnet publish Api/Api.csproj --configuration Release --no-restore --output /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0.15@sha256:12b1135f5f8b3c0a214f2a680ff2033dff4f684f445d6c697d9524ceeb303586 AS runtime
WORKDIR /app
COPY --from=publish /app .
# Non-root user of the image, UID 1654, as the restricted profile wants;
# Kestrel listens on 8080, the ASPNETCORE_HTTP_PORTS of the image (research
# RS-18).
USER $APP_UID
ENTRYPOINT ["dotnet", "Api.dll"]
