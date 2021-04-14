import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydro_sdk/registry/dto/getPackageDto.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart';

import 'package:hydro_sdk/build-project/projectBuilder.dart';
import 'package:hydro_sdk/build-project/sha256Data.dart';
import 'package:hydro_sdk/projectConfig/projectConfig.dart';
import 'package:hydro_sdk/projectConfig/projectConfigComponent.dart';
import 'package:hydro_sdk/projectConfig/projectConfigComponentChunk.dart';
import 'package:hydro_sdk/registry/dto/createComponentDto.dart';
import 'package:hydro_sdk/registry/dto/createPackageDto.dart';
import 'package:hydro_sdk/registry/dto/createProjectDto.dart';
import 'package:hydro_sdk/registry/dto/createUserDto.dart';
import 'package:hydro_sdk/registry/dto/loginUserDto.dart';
import 'package:hydro_sdk/registry/dto/sessionDto.dart';
import 'package:hydro_sdk/registry/registryApi.dart';

final registryTestUrl = Platform.environment["REGISTRY_TEST_URL"];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  group("", () {
    test("", () async {
      final api = RegistryApi(baseUrl: registryTestUrl);

      final username = "test${Uuid().v4()}";
      final password = Uuid().v4();

      final projectName = "test-project-${Uuid().v4()}";
      final projectDescription = "test project descrption ${Uuid().v4()}";

      final componentName = "test-component-${Uuid().v4()}";
      final componentDescription = "test component descrption ${Uuid().v4()}";

      final response = await api.createUser(
          dto: CreateUserDto(
        username: username,
        password: password,
      ));

      expect(response, isNotNull);
      expect(response, true);

      var createProjectResponse = await api.createProject(
        dto: CreateProjectDto(
          name: projectName,
          description: projectDescription,
        ),
        sessionDto: SessionDto.empty(),
      );

      expect(createProjectResponse, isNull);

      final loginResponse = await api.login(
          dto: LoginUserDto(
        username: username,
        password: password,
      ));

      expect(loginResponse, isNotNull);
      expect(loginResponse.authenticatedUser.username, username);

      createProjectResponse = await api.createProject(
        dto: CreateProjectDto(
          name: projectName,
          description: projectDescription,
        ),
        sessionDto: loginResponse,
      );

      expect(createProjectResponse, isNotNull);
      expect(createProjectResponse.name, projectName);
      expect(createProjectResponse.description, projectDescription);

      var canUpdateProjectResponse = await api.canUpdateProjects(
        sessionDto: SessionDto.empty(),
      );

      expect(canUpdateProjectResponse, isNull);

      canUpdateProjectResponse = await api.canUpdateProjects(
        sessionDto: loginResponse,
      );

      expect(canUpdateProjectResponse, isNotNull);
      expect(canUpdateProjectResponse.first.name, createProjectResponse.name);
      expect(canUpdateProjectResponse.first.description,
          createProjectResponse.description);

      var createComponentResponse = await api.createComponent(
        dto: CreateComponentDto(
          name: componentName,
          description: componentDescription,
          projectId: createProjectResponse.id,
        ),
        sessionDto: SessionDto.empty(),
      );

      expect(createComponentResponse, isNull);

      createComponentResponse = await api.createComponent(
        dto: CreateComponentDto(
          name: componentName,
          description: componentDescription,
          projectId: createProjectResponse.id,
        ),
        sessionDto: loginResponse,
      );

      expect(createComponentResponse, isNotNull);
      expect(createComponentResponse.name, componentName);
      expect(createComponentResponse.description, componentDescription);

      var canUpdateComponentResponse = await api.canUpdateComponents(
        sessionDto: loginResponse,
      );

      expect(canUpdateComponentResponse, isNotNull);
      expect(
          canUpdateComponentResponse.first.name, createComponentResponse.name);
      expect(canUpdateComponentResponse.first.description,
          createComponentResponse.description);

      final projectConfig = ProjectConfig(project: projectName, components: [
        ProjectConfigComponent(name: componentName, chunks: [
          ProjectConfigComponentChunk(
            type: ProjectConfigComponentChunkType.mountable,
            entryPoint: "ota/index.ts",
          )
        ])
      ]);

      final Map<String, dynamic> package =
          jsonDecode(await File("package.json").readAsString());

      final platformName = Platform.isMacOS
          ? "darwin"
          : Platform.isWindows
              ? "win32"
              : Platform.isLinux
                  ? "linux"
                  : "";

      final ProjectBuilder projectBuilder = ProjectBuilder(
        projectConfig: projectConfig,
        ts2hc:
            ".hydroc${path.separator}${package["dependencies"]["@hydro-sdk/hydro-sdk"]}${path.separator}sdk-tools${path.separator}ts2hc-$platformName-x64",
        cacheDir:
            ".hydroc${path.separator}${package["dependencies"]["@hydro-sdk/hydro-sdk"]}",
        profile: "release",
        signingKey: createComponentResponse.publishingPrivateKey,
        outDir: ".",
      );

      await projectBuilder.build(signManifest: true);

      final createPackageResponse = await api.createPackage(
          createPackageDto: CreatePackageDto(
        publishingPrivateKeySha256:
            sha256Data(createComponentResponse.publishingPrivateKey.codeUnits),
        otaPackageBase64:
            base64Encode(await File("$componentName.ota").readAsBytes()),
        componentName: componentName,
        displayVersion: "",
        description: "",
        readmeMd: "",
        pubspecYaml: "",
        pubspecLock: "",
      ));

      expect(createPackageResponse, isNotNull);

      var latestPackageUri = await api.getLatestPackageUri(
          getPackageDto: GetPackageDto(
        sessionId: Uuid().v4(),
        projectName: projectName,
        componentName: componentName,
        releaseChannelName: "latest",
        currentPackageId: "",
      ));

      expect(latestPackageUri.statusCode, 201);
      expect(latestPackageUri.body, isNotNull);
      expect(latestPackageUri.body, isNotEmpty);

      final downloadResponse = await get(latestPackageUri.body);
      expect(downloadResponse.statusCode, 200);
      expect(downloadResponse.body, isNotEmpty);

      final rawPackage = base64Decode(downloadResponse.body);

      expect(downloadResponse.body,
          base64Encode(await File("$componentName.ota").readAsBytes()));

      final decodedBzip2 = BZip2Decoder().decodeBytes(rawPackage);

      expect(decodedBzip2, isNotNull);

      final decodedTar = TarDecoder().decodeBytes(decodedBzip2);

      expect(decodedTar, isNotNull);
    }, tags: "registry", timeout: const Timeout(Duration(minutes: 5)));
  });
}
