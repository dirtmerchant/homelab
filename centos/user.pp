user { 'tux':
  managehome => true,
  groups     => ['wheel', 'users'],
  password   => pw_hash('Password1','SHA-512','random'),
}
