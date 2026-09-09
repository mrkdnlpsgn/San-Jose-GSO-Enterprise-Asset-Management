# Builds the Android APK without needing Flutter/Android SDK installed locally.
# Usage: see build-apk.ps1 / build-apk.sh
FROM ghcr.io/cirruslabs/flutter:stable

WORKDIR /app
COPY . .

RUN flutter pub get
RUN flutter build apk --release
