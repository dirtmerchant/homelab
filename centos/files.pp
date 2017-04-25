File {
  owner  => 'root',
  group  => 'wheel',
  mode   => '0664',
  ensure => 'file',
}

file { '/tmp/puppet':
  ensure => 'directory',
}

file { '/tmp/puppet/file1': }
file { '/tmp/puppet/file2': }
file { '/tmp/puppet/file3':
  mode => '0775',
}
