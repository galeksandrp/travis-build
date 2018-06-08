require 'shellwords'
require 'travis/build/appliances/base'

module Travis
  module Build
    module Appliances
      class Services < Base
        SERVICES = {
          'hbase'        => 'hbase-master', # for HBase status, see travis-ci/travis-cookbooks#40. MK.
          'memcache'     => 'memcached',
          'neo4j-server' => 'neo4j',
          'rabbitmq'     => 'rabbitmq-server',
          'redis'        => 'redis-server'
        }

        def apply
          sh.fold 'services' do
            services.each do |name|
              service_apply_method = "apply_#{name}"
              if respond_to?(service_apply_method)
                send(service_apply_method)
                next
              end
              command = start_daemon_command(name)
              sh.cmd command, sudo: true, assert: false, echo: true, timing: true
            end
            sh.raw 'sleep 3'
          end
        end

        def apply?
          services.any? && data.is_linux?
        end

        def start_daemon_command(name)
          if data.has_upstart?
            return "service #{name.shellescape} start"
          elsif data.has_systemd?
            return "systemctl start #{name.shellescap}"
          end
        end
          
        def apply_mongodb
          if data.is_precise?
            command = 'service mongod start'
          elsif data.is_trusty?
            command = 'service mongodb start'
          else
            command = 'systemctl start mongodb'
          end
          sh.cmd command, assert: false, echo: true, timing: true, sudo: true
        end

        def apply_mysql
          sh.raw <<~BASH
            travis_mysql_ping() {
              local i timeout=10
              until (( i++ >= $timeout )) || mysql <<<'select 1;' >&/dev/null; do sleep 1; done
              if (( i > $timeout )); then
                echo -e "${ANSI_RED}MySQL did not start within ${timeout} seconds${ANSI_RESET}"
              fi
              unset -f travis_mysql_ping
            }
          BASH
          command = start_daemon_command('mysql')
          sh.cmd command, sudo: true, assert: false, echo: true, timing: true
          sh.cmd 'travis_mysql_ping', assert: false, echo: false, timing: false
        end

        def apply_postgresql
          # This will be handled by addons if used
          return if data[:config][:addons].key? :postgresql
          if data.has_upstart?
            sh.cmd 'service postgresql start', assert: false, sudo: true
          else
            sh.cmd 'systemctl start postgresql@9.6-main', assert: false, sudo: true, echo: true
          end
        end

        private

          def services
            @services ||= Array(config[:services]).map do |name|
              normalize(name)
            end
          end

          def normalize(name)
            name = name.to_s.downcase
            SERVICES[name] ? SERVICES[name] : name
          end
      end
    end
  end
end
