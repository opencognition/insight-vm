$ar_databases = ['activerecord_unittest', 'activerecord_unittest2']
$as_vagrant   = 'sudo -u vagrant -H bash -l -c'
$home         = '/home/vagrant'

# Pick a Ruby version modern enough, that works in the currently supported Rails
# versions, and for which RVM provides binaries.
$ruby_version = '2.1.1'

# Pick a Rails version modern enough, that works in the currently supported Rails
# versions, and for which RVM provides binaries.
$rails_version = '4.1.1'

Exec {
  path => ['/usr/sbin', '/usr/bin', '/sbin', '/bin']
}

# --- Preinstall Stage ---------------------------------------------------------

stage { 'preinstall':
  before => Stage['main']
}

class apt_get_update {
  exec { 'apt-get -y update':
    unless => "test -e ${home}/.rvm"
  }
}
class { 'apt_get_update':
  stage => preinstall
}

# --- SQLite -------------------------------------------------------------------

package { ['sqlite3', 'libsqlite3-dev']:
  ensure => installed;
}

# --- PostgreSQL ---------------------------------------------------------------

class install_postgres {

  class { 'postgresql::globals':
    encoding            => 'UTF8',
    locale              => 'en_NG',
    manage_package_repo => true,
    version             => '9.3',
  }->
  class { 'postgresql::server':
    ip_mask_deny_postgres_user => '0.0.0.0/32',
    ip_mask_allow_all_users    => '0.0.0.0/0',
    listen_addresses           => '*',
#    ipv4acls                   => ['host all all 10.0.2.2/32 trust'],
    manage_firewall            => false, #true,
    postgres_password          => 'postgres',
  }

  postgresql::server::role { 'insight':
    password_hash => postgresql_password('insight', 'password'),
    superuser => true,
  }

  postgresql::server::db { 'insight_development':
    user     => 'insight',
    password => postgresql_password('insight', 'password'),
  }

  package { 'libpq-dev':
    ensure => installed,
  }

  package { 'postgresql-contrib':
    ensure  => installed,
    require => Class['postgresql::server'],
  }

  postgresql::server::pg_hba_rule { 'allow application network':
    description => "Open up postgresql for access from 10.0.2.2/32",
    type => 'host',
    database => 'all',
    user => 'all',
    address => '10.0.2.2/32',
    auth_method => 'trust',
  }

}
class { 'install_postgres': }

exec { "/usr/bin/psql -d template1 -c 'CREATE EXTENSION \"uuid-ossp\";'":
  user   => "postgres",
  unless => "/usr/bin/psql -d template1 -c '\\dx' | grep 'uuid-ossp'",
  require => Class['install_postgres'],
}

# --- Memcached ----------------------------------------------------------------

class { 'memcached': }

# --- Packages -----------------------------------------------------------------

package { 'curl':
  ensure => installed
}

package { 'build-essential':
  ensure => installed
}

package { 'git-core':
  ensure => installed
}

# Nokogiri dependencies.
package { ['libxml2', 'libxml2-dev', 'libxslt1-dev']:
  ensure => installed
}

# ExecJS runtime.
package { 'nodejs':
  ensure => installed
}

# --- Ruby ---------------------------------------------------------------------

exec { 'install_rvm':
  command => "${as_vagrant} 'curl -L https://get.rvm.io | bash -s stable'",
  creates => "${home}/.rvm/bin/rvm",
  require => Package['curl'],
}

exec { 'install_ruby':
  # We run the rvm executable directly because the shell function assumes an
  # interactive environment, in particular to display messages or ask questions.
  # The rvm executable is more suitable for automated installs.
  #
  # use a ruby patch level known to have a binary
  command => "${as_vagrant} '${home}/.rvm/bin/rvm install ruby-${ruby_version} --binary --autolibs=enabled && rvm alias create default ${ruby_version}'",
  creates => "${home}/.rvm/bin/ruby",
  require => Exec['install_rvm'],
}

# RVM installs a version of bundler, but for edge Rails we want the most recent one.
exec { "${as_vagrant} 'gem install bundler --no-rdoc --no-ri'":
  creates => "${home}/.rvm/bin/bundle",
  require => Exec['install_ruby'],
}

# --- Locale -------------------------------------------------------------------

# Needed for docs generation.
exec { 'update-locale':
  command => 'update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8',
}

# --- Rails---------------------------------------------------------------------

# Install Rails with gem.
exec { "${as_vagrant} 'gem install rails --no-rdoc --no-ri'":
  creates => "${home}/.rvm/bin/rails",
  require => Exec['install_ruby'],
}

