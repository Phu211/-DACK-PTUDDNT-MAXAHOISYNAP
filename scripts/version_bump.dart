// Dart script để tăng version trong pubspec.yaml
// Usage: dart run scripts/version_bump.dart [major|minor|patch]

import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run scripts/version_bump.dart [major|minor|patch]');
    print('  major: Tăng MAJOR version (1.0.0 -> 2.0.0)');
    print('  minor: Tăng MINOR version (1.0.0 -> 1.1.0)');
    print('  patch: Tăng PATCH version (1.0.0 -> 1.0.1)');
    exit(1);
  }

  final type = args[0].toLowerCase();
  if (!['major', 'minor', 'patch'].contains(type)) {
    print('Error: Type must be "major", "minor", or "patch"');
    exit(1);
  }

  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('Error: pubspec.yaml not found!');
    exit(1);
  }

  // Đọc file
  final content = pubspecFile.readAsStringSync();

  // Tìm và parse version
  final versionRegex = RegExp(r'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)');
  final match = versionRegex.firstMatch(content);

  if (match == null) {
    print('Error: Could not parse version from pubspec.yaml');
    exit(1);
  }

  var major = int.parse(match.group(1)!);
  var minor = int.parse(match.group(2)!);
  var patch = int.parse(match.group(3)!);
  var versionCode = int.parse(match.group(4)!);

  print('Current version: $major.$minor.$patch+$versionCode');

  // Tăng version theo type
  switch (type) {
    case 'major':
      major++;
      minor = 0;
      patch = 0;
      print('Bumping MAJOR version');
      break;
    case 'minor':
      minor++;
      patch = 0;
      print('Bumping MINOR version');
      break;
    case 'patch':
      patch++;
      print('Bumping PATCH version');
      break;
  }

  // Luôn tăng versionCode
  versionCode++;

  final newVersion = '$major.$minor.$patch+$versionCode';

  // Thay thế version trong file
  final newContent = content.replaceFirst(
    versionRegex,
    'version: $newVersion',
  );

  // Ghi lại file
  pubspecFile.writeAsStringSync(newContent);

  print('Version updated to: $newVersion');
  print('');
  print('Next steps:');
  print('  1. Review the changes in pubspec.yaml');
  print('  2. Commit the version change');
  print('  3. Build your app: flutter build apk --release');
}

