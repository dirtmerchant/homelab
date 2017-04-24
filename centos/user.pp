user { 'tux':
  managehome => true,
  groups     => ['wheel', 'users'],
  ensure     => present,
}
