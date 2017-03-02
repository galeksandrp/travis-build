module Travis
  module Build
    class Script
      class Dart < Script
        DEFAULTS = {
          dart: 'stable',
          with_content_shell: false,
          install_dartium: false,
          xvfb: true
        }

        attr_reader :task

        def initialize(*args)
          super

          @task = config[:dart_tasks] || {}
          @task = {task.to_sym => true} if task.is_a?(String)
          @task[:install_dartium] = config[:install_dartium] unless task.include?(:install_dartium)
          @task[:xvfb] = config[:xvfb] unless task.include?(:xvfb)
          @task[:dart] ||= config[:dart]

          # Run "pub run test" by default if no other tasks are specified.
          @task[:test] ||= true if !@task[:dartanalyzer] && !@task[:dartfmt]
        end

        def configure
          super

          if config[:with_content_shell]
            if config.include?(:dart_tasks)
              sh.failure "with_content_shell can't be used with dart_tasks."
              return
            elsif config[:install_dartium]
              sh.failure "with_content_shell can't be used with install_dartium."
              return
            elsif !config[:xvfb]
              sh.failure "with_content_shell can't be used with xvfb."
              return
            end

            sh.fold "deprecated.with_content_shell" do
              sh.deprecate <<MESSAGE
DEPRECATED: with_content_shell is deprecated. Instead use:

    dart_tasks:
    - test: --platform vm
    - test: --platform firefox
    - test: --platform dartium
      install_dartium: true
MESSAGE
            end

            sh.fold 'content_shell_dependencies_install' do
              sh.echo 'Installing Content Shell dependencies', ansi: :yellow

              # Enable Multiverse Packages:
              sh.cmd "sudo sh -c 'echo \"deb http://gce_debian_mirror.storage.googleapis.com precise contrib non-free\" >> /etc/apt/sources.list'"
              sh.cmd "sudo sh -c 'echo \"deb http://gce_debian_mirror.storage.googleapis.com precise-updates contrib non-free\" >> /etc/apt/sources.list'"
              sh.cmd "sudo sh -c 'apt-get update'"

              # Pre-accepts MSFT Fonts EULA:
              sh.cmd "sudo sh -c 'echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections'"

              # Install all dependencies:
              sh.cmd "sudo sh -c 'apt-get install --no-install-recommends -y -q chromium-browser libudev0 ttf-kochi-gothic ttf-kochi-mincho ttf-mscorefonts-installer ttf-indic-fonts ttf-dejavu-core ttf-indic-fonts-core fonts-thai-tlwg msttcorefonts xvfb'"
            end
          end
        end

        def export
          super

          sh.export 'TRAVIS_DART_VERSION', task[:dart], echo: false
        end

        def setup
          super

          sh.echo 'Dart for Travis-CI is not officially supported, ' \
            'but is community maintained.', ansi: :green
          sh.echo 'Please file any issues using the following link',
            ansi: :green
          sh.echo '  https://github.com/travis-ci/travis-ci/issues' \
            '/new?labels=community:dart', ansi: :green
          sh.echo 'and mention `@nex3` and \`@a14n\`' \
            ' in the issue', ansi: :green

          sh.export 'PUB_ENVIRONMENT', 'travis'

          sh.fold 'dart_install' do
            sh.echo 'Installing Dart', ansi: :yellow
            sh.cmd "curl #{archive_url}/sdk/dartsdk-#{os}-x64-release.zip > $HOME/dartsdk.zip"
            sh.cmd "unzip $HOME/dartsdk.zip -d $HOME > /dev/null"
            sh.cmd "rm $HOME/dartsdk.zip"
            sh.cmd 'export DART_SDK="$HOME/dart-sdk"'
            sh.cmd 'export PATH="$DART_SDK/bin:$PATH"'
            sh.cmd 'export PATH="$HOME/.pub-cache/bin:$PATH"'
          end

          if task[:install_dartium]
            sh.fold 'dartium_install' do
              sh.echo 'Installing Dartium', anis: :yellow

              sh.cmd "mkdir $HOME/dartium"
              sh.cmd "cd $HOME/dartium"
              sh.cmd "curl #{archive_url}/dartium/dartium-#{os}-x64-release.zip > dartium.zip"
              sh.cmd "unzip dartium.zip > /dev/null"
              sh.cmd "rm dartium.zip"
              sh.cmd 'dartium_dir="${PWD%/}/$(ls)"'

              # The executable has to be named "dartium" in order for the test
              # runner to find it.
              if os == 'macos'
                sh.cmd 'ln -s "$dartium_dir/Chromium.app/Contents/MacOS/Chromium" dartium'
              else
                sh.cmd 'ln -s "$dartium_dir/chrome" dartium'
              end

              sh.cmd 'export PATH="$PWD:$PATH"'
              sh.cmd "cd -"
            end
          end

          if config[:with_content_shell]
            if config[:os] != 'linux'
              sh.failure 'Content shell only supported on Linux'
            end
            sh.fold 'content_shell_install' do
              sh.echo 'Installing Content Shell', ansi: :yellow

              # Download and install Content Shell
              sh.cmd "mkdir $HOME/content_shell"
              sh.cmd "cd $HOME/content_shell"
              sh.cmd "curl #{archive_url}/dartium/content_shell-linux-x64-release.zip > content_shell.zip"
              sh.cmd "unzip content_shell.zip > /dev/null"
              sh.cmd "rm content_shell.zip"
              sh.cmd 'export PATH="${PWD%/}/$(ls):$PATH"'
              sh.cmd "cd -"
            end
          end
        end

        def announce
          super

          sh.cmd 'dart --version'
          sh.echo ''
        end

        def install
          sh.if '-f pubspec.yaml' do
            sh.fold 'pub_get' do
              sh.cmd "pub get"
            end
          end
        end

        def script
          # tests with test package
          sh.if package_installed?('test'), raw: true do
            if config[:with_content_shell]
              sh.export 'DISPLAY', ':99.0'
              sh.cmd 'sh -e /etc/init.d/xvfb start'
              # give xvfb some time to start
              sh.cmd 't=0; until (xdpyinfo -display :99 &> /dev/null || test $t -gt 10); do sleep 1; let t=$t+1; done'
              sh.cmd 'pub run test -p vm -p content-shell -p firefox'
            else
              pub_run_test
            end
          end
          # tests with test_runner for old tests written with unittest package
          sh.elif package_installed?('unittest'), raw: true do
            sh.fold "deprecated.unittest" do
              sh.deprecate <<MESSAGE
DEPRECATED: The unittest package is deprecated. Please upgrade to the test
package. See https://github.com/dart-lang/test#readme.
MESSAGE
            end

            sh.fold 'test_runner_install' do
              sh.echo 'Installing Test Runner', ansi: :yellow
              sh.cmd 'pub global activate test_runner'
            end

            if config[:with_content_shell]
              sh.cmd 'xvfb-run -s "-screen 0 1024x768x24" pub global run test_runner --disable-ansi'
            else
              sh.cmd 'pub global run test_runner --disable-ansi --skip-browser-tests'
            end
          end

          dartanalyzer
          dartfmt
        end

        private

          def pub_run_test
            return unless (args = task[:test])
            args = args.is_a?(String) ? " #{args}" : ""

            # Mac OS doesn't need or support xvfb-run.
            xvfb_run = 'xvfb-run -s "-screen 0 1024x768x24" '
            xvfb_run = '' if task[:xvfb] == false || os == "macos"
            sh.cmd "#{xvfb_run}pub run test#{args}"
          end

          def dartanalyzer
            return unless (args = task[:dartanalyzer])
            args = '.' unless args.is_a?(String)
            sh.cmd "dartanalyzer #{args}"
          end

          def dartfmt
            return unless (args = task[:dartfmt])
            if args.is_a?(String)
              sh.echo "dartfmt arguments aren't supported.", ansi: :red
            end

            sh.if package_installed?('dart_style'), raw: true do
              sh.raw 'function dartfmt() { pub run dart_style:format "$@"; }'
            end

            sh.cmd 'unformatted=`dartfmt -n .`'
            sh.if '! -z "$unformatted"' do
              sh.echo "Files are unformatted:", ansi: :red
              sh.echo "$unformatted"
              sh.failure ""
            end
          end

          def package_installed?(package)
            "[[ -d packages/#{package} ]] || grep -q ^#{package}: .packages 2> /dev/null"
          end

          def os
            config[:os] == 'osx' ? 'macos' : 'linux'
          end

          def archive_url
            urlEnd = ''
            # support of "dev" or "stable"
            if ["stable", "dev"].include?(task[:dart])
              urlEnd = "#{task[:dart]}/release/latest"
            # support of "stable/release/1.15.0" or "be/raw/110749"
            elsif task[:dart].include?("/")
              urlEnd = task[:dart]
            # support of dev versions like "1.16.0-dev.2.0" or "1.16.0-dev.2.0"
            elsif task[:dart].include?("-dev")
              urlEnd = "dev/release/#{task[:dart]}"
            # support of stable versions like "1.14.0" or "1.14.1"
            else
              urlEnd = "stable/release/#{task[:dart]}"
            end
            "https://storage.googleapis.com/dart-archive/channels/#{urlEnd}"
          end
      end
    end
  end
end
