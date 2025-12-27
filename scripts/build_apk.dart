// Script tự động tăng version và build APK
// Usage: dart run scripts/build_apk.dart [patch|minor|major] [--no-version-bump]

import 'dart:io';

void main(List<String> args) async {
  String versionType = 'patch';
  bool noVersionBump = false;

  // Parse arguments
  for (var arg in args) {
    if (arg == '--no-version-bump') {
      noVersionBump = true;
    } else if (['patch', 'minor', 'major'].contains(arg)) {
      versionType = arg;
    }
  }

  print('========================================');
  print('  Synap - Auto Build APK Script');
  print('========================================');
  print('');

  // Bước 1: Tăng version
  if (!noVersionBump) {
    print('Step 1: Bumping version ($versionType)...');
    final versionResult = await Process.run(
      'dart',
      ['run', 'scripts/version_bump.dart', versionType],
    );
    if (versionResult.exitCode != 0) {
      print('Error: Failed to bump version!');
      exit(1);
    }
    print('');
  } else {
    print('Step 1: Skipping version bump (--no-version-bump flag)');
    print('');
  }

  // Bước 2: Clean build
  print('Step 2: Cleaning build...');
  final cleanResult = await Process.run('flutter', ['clean']);
  if (cleanResult.exitCode != 0) {
    print('Error: flutter clean failed!');
    exit(1);
  }
  print('');

  // Bước 3: Get dependencies
  print('Step 3: Getting dependencies...');
  final pubGetResult = await Process.run('flutter', ['pub', 'get']);
  if (pubGetResult.exitCode != 0) {
    print('Error: flutter pub get failed!');
    exit(1);
  }
  print('');

  // Bước 4: Build APK
  print('Step 4: Building APK (release)...');
  final buildResult = await Process.run('flutter', ['build', 'apk', '--release']);
  if (buildResult.exitCode != 0) {
    print('Error: Build failed!');
    exit(1);
  }
  print('');

  // Bước 5: Hiển thị thông tin
  print('========================================');
  print('  Build completed successfully!');
  print('========================================');
  print('');
  print('APK location:');
  print('  build/app/outputs/flutter-apk/app-release.apk');
  print('');
  print('To install on device:');
  print('  adb install build/app/outputs/flutter-apk/app-release.apk');
  print('');
}

