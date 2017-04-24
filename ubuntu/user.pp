user { 'tux':
  managehome => true,
  groups     => ['sudo', 'users'],
  ensure     => present,
}
