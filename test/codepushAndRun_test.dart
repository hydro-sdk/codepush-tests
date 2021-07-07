import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydro_sdk/registry/dto/createMockUserDto.dart';
import 'package:hydro_sdk/runComponent/runComponent.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;

import 'package:hydro_sdk/build-project/projectBuilder.dart';
import 'package:hydro_sdk/build-project/sha256Data.dart';
import 'package:hydro_sdk/projectConfig/projectConfig.dart';
import 'package:hydro_sdk/projectConfig/projectConfigComponent.dart';
import 'package:hydro_sdk/projectConfig/projectConfigComponentChunk.dart';
import 'package:hydro_sdk/registry/dto/createComponentDto.dart';
import 'package:hydro_sdk/registry/dto/createPackageDto.dart';
import 'package:hydro_sdk/registry/dto/createProjectDto.dart';
import 'package:hydro_sdk/registry/dto/sessionDto.dart';
import 'package:hydro_sdk/registry/registryApi.dart';

final registryTestHost = Platform.environment["REGISTRY_TEST_HOST"];
final registryTestPort =
    int.tryParse(Platform.environment["REGISTRY_TEST_PORT"] ?? "");
final registryTestScheme = Platform.environment["REGISTRY_TEST_SCHEME"];

class CustomBindings extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  CustomBindings();
  testWidgets("", (WidgetTester tester) async {
    final api = RegistryApi(
      scheme: registryTestScheme,
      host: registryTestHost,
      port: registryTestPort,
    );

    final username = "test${Uuid().v4()}";

    final projectName = "codepush-test-project-${Uuid().v4()}";
    final projectDescription =
        "codepush test project descrption ${Uuid().v4()}";

    final componentName = "codepush-test-component-${Uuid().v4()}";
    final componentDescription =
        "codepush test component descrption ${Uuid().v4()}";

    final response = await api.createMockUser(
        dto: CreateMockUserDto(
      displayName: username,
      email: "${api.hash(Uuid().v4())}@example.com",
      password: Uuid().v4(),
    ));

    expect(response, isNotNull);
    expect(response, isNotEmpty);

    var createProjectResponse = await api.createProject(
      dto: CreateProjectDto(
        name: projectName,
        description: projectDescription,
      ),
      sessionDto: SessionDto.empty(),
    );

    expect(createProjectResponse, isNull);

    createProjectResponse = await api.createProject(
      dto: CreateProjectDto(
        name: projectName,
        description: projectDescription,
      ),
      sessionDto: SessionDto(
        authToken: response,
      ),
    );

    expect(createProjectResponse, isNotNull);
    expect(createProjectResponse.name, projectName);
    expect(createProjectResponse.description, projectDescription);

    var canUpdateProjectResponse = await api.canUpdateProjects(
      sessionDto: SessionDto.empty(),
    );

    expect(canUpdateProjectResponse, isNull);

    canUpdateProjectResponse = await api.canUpdateProjects(
      sessionDto: SessionDto(
        authToken: response,
      ),
    );

    expect(canUpdateProjectResponse, isNotNull);

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
      sessionDto: SessionDto(
        authToken: response,
      ),
    );

    expect(createComponentResponse, isNotNull);
    expect(createComponentResponse.name, componentName);
    expect(createComponentResponse.description, componentDescription);

    var canUpdateComponentResponse = await api.canUpdateComponents(
      sessionDto: SessionDto(
        authToken: response,
      ),
    );

    expect(canUpdateComponentResponse, isNotNull);
    expect(canUpdateComponentResponse.first.name, createComponentResponse.name);
    expect(canUpdateComponentResponse.first.description,
        createComponentResponse.description);

    final projectConfig = ProjectConfig(
      project: projectName,
      components: [
        ProjectConfigComponent(
          name: componentName,
          chunks: [
            ProjectConfigComponentChunk(
              type: ProjectConfigComponentChunkType.mountable,
              entryPoint: "ota/index.ts",
              baseUrl: "ota",
            ),
          ],
        ),
      ],
    );

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
      displayVersion: "1.2.3",
      description: "From a codepush test",
      readmeMd: """
# Distantia et cepisse sedes

## Etiam poena Cyllenide longa ante

Lorem markdownum sibi; frustra
[nymphae](http://incertam-philemona.com/adfata-cunctos) et nunc, dat subit et
spatium solo, furta dicere. Potentia aer solus Eurydicen videt et vigor *illic*
amnis quod vaccae moraque. Altaque inflataque Cyllaron et vires vacuaque pudore
hoc viperei exclusura vosque inmortalis voces. Ergo ipse demittant minus, mox,
Musa aetas, et avis dis sed. Conplexa fastus pater cruentae metuens, et refugit
ludit, o **praedae**, tum!

- Qui procos iam caelo data auxilium osque
- Porrecta parentes neque
- Lege Iovi carpit e repugnat tigno simul

## Faces inde micantes visus

Quicquam [aether ab](http://www.inablato.io/) nimia sacra. Adpositi quid.

> *Qua* lege omnia erat capillis misce quae incerti indutus ostendit et aram
> imber! Ad vultus dici, noctis, ramis proculcat quoque, suadet, currus. Pro
> forsitan inest subigebat maiores. Pharetra ne tempora animo Leucippusque
> quoque fidum nati canunt vincula agrestem recuset virtutis, coloni. Datae
> *per* longas humus pronepos.

## Visa hic longo alterius indicet aurum certamine

Inque inpulit ubi volat et omnia comitata Hymettia arbore pro **furit ubi
tempore** pectus est nec. Spicula pars Mycenae multum, noctes geminae in inquit
iampridem tectus, cui. Pace dixit grave astu non sensit inponit vindice Idaei
refer lumina sinistra? Erat mea; in argento habuit; lingua ad quae penthea
oculis *litora*. Mihi perque, ambo [et memorabat](http://praestatenymphae.io/),
iam primos proque Iuno Lycias hunc qui agmina creatus dant est iterum sacris.

- Nunc patruelis indignata esse herba Proteu trepidosque
- Meorum metiris
- Nimios caute
- Fontis dira rex mugitu positamque haec sapiente

## Insidiosa pisces supplentur quem ubi

Illos [exaestuat](http://omnisipse.net/) meorum! Ter sacris tamen, mensis orbe
pelagi sacros tua *agitantem pudore*, enim in esse precor sceleris. Quia cur,
venit virgineos quidem, Styga *prohibete viderunt*, in velum saxa sed *palustri
ungues* signaque nympha: et. Iussa quoque illo, meque, sermone ait, fatigat
venti hospitis sonos horum. Quam est quorum referens palaestrae mersit Neleius
monitisque abstraxit laqueis, et cum coepit?

## Lux amor securibus

Omnis datas alvo coniuge factus in occupat haurit de claro pulsant, postquam.
Fatali in in aut haec progeniem, cadunt o veniunt quae, erit, una. Gelida mollia
recens dubitas placeat de quoque temptat totidemque adimam.

Attonitus fertur; diu standi forsitan **nulli** acumine lacrimarum **inde**.
Soceri et venit; cum uno cornua huic corpore sequiturque urbis excussam: tenet
inertes saepe disiecit vocesque de. Fecit pro *vota et* tactus possunt,
patruelibus hominis recedit Scyllae hosti? Comminus iussae susurra sibi,
fugientia nymphas. Nimium Diamque caerula maritum montibus, ad est casas rigorem
quod unam Ulixem.
""",
      pubspecYaml: "",
      pubspecLock: "",
    ));

    expect(createPackageResponse.statusCode, 201);

    await tester.pumpWidget(RunComponent(
      project: projectName,
      component: componentName,
      releaseChannel: "latest",
      registryApi: api,
    ));

    await tester.pumpAndSettle();

    var exception = tester.takeException();
    expect(exception, isNull);

    await Future.delayed(Duration(seconds: 60));

    await tester.pumpAndSettle();

    exception = tester.takeException();
    expect(exception, isNull);

    expect(find.byKey(const Key("counter")), findsOneWidget);
    expect(find.byKey(const Key("increment")), findsOneWidget);
    expect(find.text("You have pushed the button this many times"),
        findsOneWidget);

    expect(find.text("0"), findsOneWidget);
    await tester.tap(find.byKey(const Key("increment")));
    await tester.pumpAndSettle();
    expect(find.text("1"), findsOneWidget);
    await tester.tap(find.byKey(const Key("increment")));
    await tester.pumpAndSettle();
    expect(find.text("2"), findsOneWidget);
  }, tags: "registry", timeout: const Timeout(Duration(minutes: 5)));
}
