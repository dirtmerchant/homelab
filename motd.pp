file { '/etc/motd': 
  content => "This is a message\n",
  ensure  => 'file',
}
