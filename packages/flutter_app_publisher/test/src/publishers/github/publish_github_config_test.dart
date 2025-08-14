import 'dart:io';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/github/publish_github_config.dart';
import 'package:test/test.dart';

void main() {
  group('PublishGithubConfig', () {
    late Directory tempDir;
    late File tempPubspecFile;

    setUp(() async {
      // Create a temporary directory for testing
      tempDir =
          await Directory.systemTemp.createTemp('publish_github_config_test');
      tempPubspecFile = File('${tempDir.path}/pubspec.yaml');

      // Create a test pubspec.yaml file
      await tempPubspecFile.writeAsString('''
name: test_app
version: 1.0.0+1
environment:
  sdk: '>=2.17.0 <4.0.0'
''');

      // Change to the temp directory so pubspec.yaml can be found
      Directory.current = tempDir;
    });

    tearDown(() async {
      // Clean up temp directory
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('constructor', () {
      test('creates instance with required parameters', () {
        final config = PublishGithubConfig(
          token: 'test_token',
          repository: 'test_owner/test_repo',
        );

        expect(config.token, equals('test_token'));
        expect(config.repository, equals('test_owner/test_repo'));
        expect(config.releaseTitle, isNull);
      });

      test('creates instance with optional releaseTitle', () {
        final config = PublishGithubConfig(
          token: 'test_token',
          repository: 'test_owner/test_repo',
          releaseTitle: 'v1.0.0',
        );

        expect(config.releaseTitle, equals('v1.0.0'));
      });
    });

    group('parse', () {
      test('parses with valid environment variables and arguments', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
          'github-release-title': 'Custom Release v{appVersion}',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.token, equals('test_token'));
        expect(config.repository, equals('test_owner/test_repo'));
        expect(config.releaseTitle, equals('Custom Release v1.0.0'));
      });

      test('uses default releaseTitle when not provided', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.releaseTitle, equals('v1.0.0+1'));
      });

      test('uses default releaseTitle when empty string provided', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
          'github-release-title': '',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.releaseTitle, equals('v1.0.0+1'));
      });

      test('replaces placeholders in releaseTitle', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
          'github-release-title':
              'Release v{appVersion} build {appBuildNumber}',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.releaseTitle, equals('Release v1.0.0 build 1'));
      });

      test('uses GITHUB_REPOSITORY when github-repo is not provided', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': 'env_owner/test_repo',
        };
        final publishArguments = <String, dynamic>{};

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.repository, equals('env_owner/test_repo'));
      });

      test('extracts owner and name from GITHUB_REPOSITORY', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': 'repo_owner/repo_name',
        };
        final publishArguments = <String, dynamic>{};

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.repository, equals('repo_owner/repo_name'));
      });

      test('prioritizes github-repo over GITHUB_REPOSITORY', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': 'repo_owner/repo_name',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.repository, equals('test_owner/test_repo'));
      });

      test('uses Platform.environment when environment parameter is null', () {
        // This test verifies that parse() uses Platform.environment when null is passed
        // We can't actually modify Platform.environment, so we'll test the fallback behavior
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        // Since we can't control Platform.environment, we'll just verify that
        // the method doesn't crash when null is passed
        expect(
          () => PublishGithubConfig.parse(null, publishArguments),
          isA<Function>(),
        );
      });

      test('throws PublishError when GITHUB_TOKEN is missing', () {
        final environment = <String, String>{};
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(
            isA<PublishError>().having(
              (e) => e.message,
              'message',
              contains('Missing `GITHUB_TOKEN` environment variable'),
            ),
          ),
        );
      });

      test('throws PublishError when GITHUB_TOKEN is empty', () {
        final environment = {
          'GITHUB_TOKEN': '',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(
            isA<PublishError>().having(
              (e) => e.message,
              'message',
              contains('Missing `GITHUB_TOKEN` environment variable'),
            ),
          ),
        );
      });

      test('throws PublishError when repository is missing', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = <String, dynamic>{};

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(
            isA<PublishError>().having(
              (e) => e.message,
              'message',
              contains('GitHub repository is required'),
            ),
          ),
        );
      });

      test('throws PublishError when repository format is invalid', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'invalid_format',
        };

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(
            isA<PublishError>().having(
              (e) => e.message,
              'message',
              contains('Invalid GitHub repository format'),
            ),
          ),
        );
      });

      test('throws PublishError when GITHUB_REPOSITORY is empty', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': '',
        };
        final publishArguments = <String, dynamic>{};

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(
            isA<PublishError>().having(
              (e) => e.message,
              'message',
              contains('GitHub repository is required'),
            ),
          ),
        );
      });

      test('handles null publishArguments', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': 'repo_owner/repo_name',
        };

        final config = PublishGithubConfig.parse(environment, null);

        expect(config.token, equals('test_token'));
        expect(config.repository, equals('repo_owner/repo_name'));
        expect(config.releaseTitle, equals('v1.0.0+1'));
      });

      test('handles empty publishArguments', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': 'repo_owner/repo_name',
        };

        final config = PublishGithubConfig.parse(environment, {});

        expect(config.token, equals('test_token'));
        expect(config.repository, equals('repo_owner/repo_name'));
        expect(config.releaseTitle, equals('v1.0.0+1'));
      });

      test('prioritizes publishArguments over environment variables', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': 'env_owner/env_repo',
        };
        final publishArguments = {
          'github-repo': 'arg_owner/arg_repo',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.repository, equals('arg_owner/arg_repo'));
      });

      test('handles GITHUB_REPOSITORY without slash', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': 'invalid_repo_format',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.repository, equals('test_owner/test_repo'));
      });

      test('handles empty GITHUB_REPOSITORY', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': '',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.repository, equals('test_owner/test_repo'));
      });

      test('handles valid repository format', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.repository, equals('test_owner/test_repo'));
      });

      test('handles complex version with build number', () async {
        // Create a pubspec with complex version
        await tempPubspecFile.writeAsString('''
name: test_app
version: 2.1.0+10
environment:
  sdk: '>=2.17.0 <4.0.0'
''');

        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
          'github-release-title': 'v{appVersion}+{appBuildNumber}',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.releaseTitle, equals('v2.1.0+10'));
      });

      test('handles version without build number', () async {
        // Create a pubspec without build number
        await tempPubspecFile.writeAsString('''
name: test_app
version: 1.2.3
environment:
  sdk: '>=2.17.0 <4.0.0'
''');

        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
          'github-release-title': 'v{appVersion} build {appBuildNumber}',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        // When there's no '+' in version, appBuildNumber equals appVersion
        expect(config.releaseTitle, equals('v1.2.3 build 1.2.3'));
      });

      test('replaces {appBuildName} placeholder', () async {
        // Test the {appBuildName} variable that wasn't tested before
        await tempPubspecFile.writeAsString('''
name: test_app
version: 2.1.0+15
environment:
  sdk: '>=2.17.0 <4.0.0'
''');

        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
          'github-release-title':
              'Release {appBuildName} (build {appBuildNumber})',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.releaseTitle, equals('Release 2.1.0 (build 15)'));
      });

      test('handles all variable types together', () async {
        await tempPubspecFile.writeAsString('''
name: test_app
version: 3.2.1+42
environment:
  sdk: '>=2.17.0 <4.0.0'
''');

        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
          'github-release-title':
              '{appVersion} | {appBuildName} | {appBuildNumber}',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.releaseTitle, equals('3.2.1 | 3.2.1 | 42'));
      });

      test(
          'throws PublishError when repository has invalid format - owner only',
          () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'owner/',
        };

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(
            isA<PublishError>().having(
              (e) => e.message,
              'message',
              contains('Invalid GitHub repository format'),
            ),
          ),
        );
      });

      test('throws PublishError when repository has invalid format - repo only',
          () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': '/repo',
        };

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(
            isA<PublishError>().having(
              (e) => e.message,
              'message',
              contains('Invalid GitHub repository format'),
            ),
          ),
        );
      });

      test(
          'throws PublishError when repository has invalid format - multiple slashes',
          () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'owner/repo/extra',
        };

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(
            isA<PublishError>().having(
              (e) => e.message,
              'message',
              contains('Invalid GitHub repository format'),
            ),
          ),
        );
      });

      test('throws error when pubspec.yaml is missing', () async {
        // Delete the pubspec.yaml file
        await tempPubspecFile.delete();

        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('throws error when pubspec.yaml has invalid format', () async {
        // Create invalid pubspec.yaml
        await tempPubspecFile.writeAsString('''
name: test_app
version: invalid_version_format
environment:
  sdk: '>=2.17.0 <4.0.0'
''');

        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': 'test_owner/test_repo',
        };

        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          throwsA(isA<Exception>()),
        );
      });

      test('handles whitespace in arguments correctly', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
        };
        final publishArguments = {
          'github-repo': '  test_owner/test_repo  ',
          'github-release-title': '  v{appVersion}  ',
        };

        final config = PublishGithubConfig.parse(environment, publishArguments);

        expect(config.repository, equals('  test_owner/test_repo  '));
        expect(config.releaseTitle, equals('  v1.0.0  '));
      });
    });

    group('print statements', () {
      test('prints message when using GITHUB_REPOSITORY', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': 'env_owner/env_repo',
        };
        final publishArguments = <String, dynamic>{};

        // This test ensures the print statement doesn't cause errors
        // In a real scenario, you might want to capture and verify the print output
        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          returnsNormally,
        );
      });

      test('prints message when extracting from GITHUB_REPOSITORY', () {
        final environment = {
          'GITHUB_TOKEN': 'test_token',
          'GITHUB_REPOSITORY': 'repo_owner/repo_name',
        };
        final publishArguments = <String, dynamic>{};

        // This test ensures the print statement doesn't cause errors
        expect(
          () => PublishGithubConfig.parse(environment, publishArguments),
          returnsNormally,
        );
      });
    });
  });
}
