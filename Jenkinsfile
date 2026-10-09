// CI for dni_peru_ocr, replacing .github/workflows/ci.yaml.
//
// Agent facts (measured, do not re-derive):
// - Agent label "node" runs flutter 3.44.0 / dart 3.12.0, a single pinned
//   SDK install. There is no fvm and no second SDK on this agent, so unlike
//   the GitHub workflow (subosito/flutter-action pinned to "3.38.x") we do
//   NOT install or switch Flutter versions here; we use whatever is already
//   on PATH. pubspec.yaml declares `flutter >=3.38.0`, which 3.44.0 satisfies.
// - The workflow's "sudo apt-get update && sudo apt-get install -y cmake
//   ninja-build" step cannot run here: the jenkins user cannot sudo. cmake
//   and ninja-build are instead baked into the agent image (jenkins-infra
//   commit 33d7628) specifically to unblock this repo's native-asset
//   (opencv_dart / dartcv4) test build. This Jenkinsfile asserts both tools
//   are already on PATH instead of trying to install them.
// - `flutter test` fails today on 3.44.0 because native asset compilation
//   needs cmake, which was missing from the probe environment ("Did not
//   find CMake on PATH" / "Failed to find cmake with version=latest" /
//   "Building native assets failed."). `flutter analyze` was proven green
//   on 3.44.0. The test stage below is NOT proven green; it is expected to
//   pass once the updated agent image (with cmake/ninja) is deployed, which
//   is being verified separately.
// - pubspec.lock is committed, but there is no evidence it resolves cleanly
//   under 3.44.0 (the probe used a plain `flutter pub get`, not
//   `--enforce-lockfile`), so we use plain `flutter pub get` here too,
//   matching what was actually probed.
// - `nproc` reports 8 in this container but the real agent only has 3 CPUs
//   available, so `flutter test` concurrency is pinned explicitly to 2
//   instead of letting Flutter auto-detect concurrency from `nproc`.

pipeline {
    agent { label 'node' }

    options {
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds(abortPrevious: true)
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {
        // Replaces the "Install native build tools (opencv_dart / dartcv4)"
        // step. That step used sudo apt-get, which is not available to the
        // jenkins user. cmake and ninja-build are now baked into the agent
        // image instead, so we only assert they are present on PATH and
        // fail loudly (naming both tools and the agent image) if not.
        stage('Assert native build tools') {
            steps {
                sh '''
                    set -eu
                    missing=""
                    if ! command -v cmake >/dev/null 2>&1; then
                        missing="${missing} cmake"
                    fi
                    if ! command -v ninja >/dev/null 2>&1; then
                        missing="${missing} ninja"
                    fi
                    if [ -n "$missing" ]; then
                        echo "Missing required tool(s):${missing}" >&2
                        echo "These must come from the Jenkins agent image, not from this build (the jenkins user cannot sudo)." >&2
                        exit 1
                    fi
                    echo "cmake and ninja found on PATH:"
                    command -v cmake
                    command -v ninja
                '''
            }
        }

        // Replaces "Install dependencies": flutter pub get at repo root.
        // Plain `pub get`, not `--enforce-lockfile`, because that is what
        // was actually probed; there is no evidence the committed
        // pubspec.lock resolves cleanly under the agent's Flutter 3.44.0.
        stage('Install dependencies') {
            steps {
                sh '''
                    set -eu
                    flutter pub get
                '''
            }
        }

        // Replaces "Analyze": flutter analyze --fatal-warnings. Proven
        // green ("No issues found") on the agent's Flutter 3.44.0 probe.
        stage('Analyze') {
            steps {
                sh '''
                    set -eu
                    flutter analyze --fatal-warnings
                '''
            }
        }

        // Replaces "Test": flutter test. Concurrency pinned to 2 (not
        // left to auto-detect via nproc, which misreports 8 cores on this
        // container when only 3 are really available). This stage is
        // expected to pass once the agent image with cmake/ninja is
        // deployed; it was not green in the probe that lacked cmake.
        stage('Test') {
            steps {
                sh '''
                    set -eu
                    flutter test --concurrency=2
                '''
            }
        }

        // Replaces "Example app analyze": pub get + analyze inside
        // example/, same two commands and same order as the workflow.
        stage('Example app analyze') {
            steps {
                dir('example') {
                    sh '''
                        set -eu
                        flutter pub get
                        flutter analyze --fatal-warnings
                    '''
                }
            }
        }
    }
}
