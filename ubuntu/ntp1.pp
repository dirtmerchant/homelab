$ntp_conf = '#Managed by Puppet
server pool.ntp.org iburst
driftfile /var/lib/ntp/drift
'
package { 'ntp': }

file { '/etc/ntp.conf':
  ensure  => 'file',
  content => $ntp_conf,
  owner   => 'root',
  group   => 'sudo',
  mode    => '0664',
}

service { 'NTP_Service':
  ensure => 'running',
  enable => 'true',
  name   => 'ntp'
}
