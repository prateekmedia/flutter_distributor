import 'dart:io';

import 'package:flutter_app_packager/src/api/app_package_maker.dart';
import 'package:flutter_app_packager/src/makers/pacman/make_pacman_config.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:shell_executor/shell_executor.dart';

class AppPackageMakerPacman extends AppPackageMaker {
  @override
  String get name => 'pacman';
  @override
  String get platform => 'linux';
  @override
  bool get isSupportedOnCurrentPlatform => Platform.isLinux;
  @override
  String get packageFormat => 'pacman';

  @override
  MakeConfigLoader get configLoader {
    return MakePacmanConfigLoader()
      ..platform = platform
      ..packageFormat = packageFormat;
  }

  @override
  Future<MakeResult> make(MakeConfig config) {
    return _make(
      config.buildOutputDirectory,
      outputDirectory: config.outputDirectory,
      makeConfig: config as MakePacmanConfig,
    );
  }

  Future<MakeResult> _make(
    Directory appDirectory, {
    required Directory outputDirectory,
    required MakePacmanConfig makeConfig,
  }) async {
    final files = makeConfig.toFilesString();

    Directory packagingDirectory = makeConfig.packagingDirectory;

    /// Need to create following directories
    /// /usr/share/$appBinaryName
    /// /usr/share/applications
    /// /usr/share/icons/hicolor/128x128/apps
    /// /usr/share/icons/hicolor/256x256/apps

    final applicationsDir =
        path.join(packagingDirectory.path, 'usr/share/applications');
    final icon128Dir = path.join(
      packagingDirectory.path,
      'usr/share/icons/hicolor/128x128/apps',
    );
    final icon256Dir = path.join(
      packagingDirectory.path,
      'usr/share/icons/hicolor/256x256/apps',
    );
    final metainfoDir =
        path.join(packagingDirectory.path, 'usr/share/metainfo');
    final mkdirProcessResult = await $('mkdir', [
      '-p',
      path.join(packagingDirectory.path, 'usr/share', makeConfig.appBinaryName),
      applicationsDir,
      if (makeConfig.metainfo != null) metainfoDir,
      if (makeConfig.icon != null) ...[icon128Dir, icon256Dir],
    ]);

    if (mkdirProcessResult.exitCode != 0) throw MakeError();

    if (makeConfig.icon != null) {
      final iconFile = File(makeConfig.icon!);
      if (!iconFile.existsSync()) {
        throw MakeError("provided icon ${makeConfig.icon} path wasn't found");
      }

      final icon128 = img.copyResize(
        img.decodeImage(iconFile.readAsBytesSync())!,
        width: 128,
        height: 128,
      );
      final icon128File =
          File(path.join(icon128Dir, '${makeConfig.appBinaryName}.png'));
      await icon128File.writeAsBytes(img.encodePng(icon128));

      final icon256 = img.copyResize(
        img.decodeImage(iconFile.readAsBytesSync())!,
        width: 128,
        height: 128,
      );
      final icon256File =
          File(path.join(icon256Dir, '${makeConfig.appBinaryName}.png'));
      await icon256File.writeAsBytes(img.encodePng(icon256));
    }
    if (makeConfig.metainfo != null) {
      final metainfoPath =
          path.join(Directory.current.path, makeConfig.metainfo!);
      final metainfoFile = File(metainfoPath);
      if (!metainfoFile.existsSync()) {
        throw MakeError("Metainfo $metainfoPath path wasn't found");
      }
      await metainfoFile.copy(
        path.join(
          metainfoDir,
          makeConfig.appBinaryName + path.extension(makeConfig.metainfo!, 2),
        ),
      );
    }

    // create & write the files got from makeConfig
    final installFile = File(path.join(packagingDirectory.path, '.INSTALL'));
    final pkgInfoFile = File(path.join(packagingDirectory.path, '.PKGINFO'));
    final desktopEntryFile =
        File(path.join(applicationsDir, '${makeConfig.appBinaryName}.desktop'));

    if (!installFile.existsSync()) installFile.createSync();
    if (!pkgInfoFile.existsSync()) pkgInfoFile.createSync();
    if (!desktopEntryFile.existsSync()) desktopEntryFile.createSync();

    await installFile.writeAsString(files['INSTALL']!);
    await pkgInfoFile.writeAsString(files['PKGINFO']!);
    await desktopEntryFile.writeAsString(files['DESKTOP']!);

    // copy the application binary to /usr/share/$appBinaryName
    await $('cp', [
      '-fr',
      '${appDirectory.path}/.',
      '${packagingDirectory.path}/usr/share/${makeConfig.appBinaryName}/',
    ]);

    // MTREE Metadata using bsdtar and fakeroot
    ProcessResult mtreeResult = await $(
      'bsdtar',
      [
        '-czf',
        '.MTREE',
        '--format=mtree',
        '--options=!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link',
        '.PKGINFO',
        '.INSTALL',
        'usr',
      ],
      environment: {
        'LANG': 'C',
      },
      workingDirectory: packagingDirectory.path,
    );
    if (mtreeResult.exitCode != 0) {
      throw MakeError(mtreeResult.stderr);
    }

    // create the pacman package using fakeroot and bsdtar
    // fakeroot -- env LANG=C bsdtar -cf - .MTREE .PKGINFO * | xz -c -z - > $pkgname-$pkgver-$pkgrel-$arch.tar.xz

    ProcessResult archiveResult = await $(
      'bsdtar',
      [
        '-cf',
        'temptar',
        '.MTREE',
        '.INSTALL',
        '.PKGINFO',
        'usr',
      ],
      environment: {
        'LANG': 'C',
      },
      workingDirectory: packagingDirectory.path,
    );
    if (archiveResult.exitCode != 0) {
      throw MakeError(archiveResult.stderr);
    }

    ProcessResult processResult = await $(
      'xz',
      [
        '-z',
        'temptar',
      ],
      workingDirectory: packagingDirectory.path,
    );

    if (processResult.exitCode != 0) {
      throw MakeError(processResult.stderr);
    }

    // copy file from temptar.xz to the makeConfig.outputFile.path
    final copyResult = await $(
      'mv',
      [
        '${packagingDirectory.path}/temptar.xz',
        makeConfig.outputFile.path,
      ],
    );
    if (copyResult.exitCode != 0) {
      throw MakeError(copyResult.stderr);
    }

    packagingDirectory.deleteSync(recursive: true);
    return MakeResult(makeConfig);
  }
}
