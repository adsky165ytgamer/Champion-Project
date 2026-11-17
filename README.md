# Cloud Box
Run inside this folder:
  flutter create --platforms=android,web --project-name cloud_box --org com.cloudbox .
  flutter pub get && flutter analyze && flutter build apk --release
(`flutter create .` keeps lib/ and pubspec.yaml; it only adds platform folders.)
Provider boundary: lib/data.dart -> AuthService / DriveAuth (unimplemented on purpose).
