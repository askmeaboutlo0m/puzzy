package Puzzy;
use Mojo::Base 'Mojolicious';
use 5.018;
use Crypt::PBKDF2;
use File::Basename        qw(dirname);
use File::Spec::Functions qw(catfile);
use Mojo::JSON            qw(true);
use Mojo::Pg;


sub _database {
  my ($self) = @_;

  my $sql = Mojo::Pg->new($ENV{DATABASE_URL} =~ s/^postgres:/postgresql:/r);

  my $migrations = catfile(dirname(__FILE__), '..', "migrations.sql");
  $sql->migrations->from_file($migrations)->migrate;

  $self->helper(db => sub { $sql->db });
}


sub _load_user {
  my ($self, $id) = @_;
  return $self->db->select(users => [qw(id name)], {id => $id})->hash;
}

sub _validate_user {
  my ($self, $name, $pass) = @_;

  my $user = $self->db->select(users => [qw(id name hash)], {name => $name})->hash
    or return undef;

  my $crypt = Crypt::PBKDF2->new(
    hash_class => 'HMACSHA2',
    iterations => 10_000,
    salt_len   => 10,
  );

  if (defined $user->{hash}) {
    return $crypt->validate($user->{hash}, $pass) ? $user->{id} : undef;
  }
  else {
    my $hash = $crypt->generate($pass);
    $self->db->update(users => {hash => $hash}, {id => $user->{id}});
    return $user->{id};
  }
}

sub _plugins {
  shift->plugin(authentication => {
    load_user     => \&_load_user,
    validate_user => \&_validate_user,
  });
}


sub _routes {
  my ($self) = @_;

  my $r  = $self->routes;
  my $w  = $r->under('/W')->to('auth#check');
  my $id = [id => qr/[0-9]+/];

  $r->get ('/login' )->to('auth#log_in' );
  $r->post('/login' )->to('auth#log_in' );
  $r->get ('/logout')->to('auth#log_out');
  $r->post('/logout')->to('auth#log_out');

  $r->get ('/annotate')->to('annotation#form');
  $r->post('/annotate')->to('annotation#build');

  $w->get   ('/:page', [format => 'txt'])->to('whatget#index_txt');
  $w->get   ('/:page/print/:category'   )->to('whatget#index_txt');
  $w->get   ('/:page'                   )->to('whatget#index');
  $w->get   ('/:page/api/item'          )->to('whatget#get_items');
  $w->post  ('/:page/api/item'          )->to('whatget#post_item');
  $w->patch ('/:page/api/item/:id', $id )->to('whatget#patch_item');
  $w->delete('/:page/api/item/:id', $id )->to('whatget#delete_item');
  $w->put   ('/:page/api/item/:id', $id )->to('whatget#restore_item');
  $w->get   ('/:page/api/history'       )->to('whatget#get_history');
  $w->post  ('/:page/api/undo'          )->to('whatget#undo');
}


sub startup {
  my ($self) = @_;
  $self->secrets(['vTdS$/("vFe9TP5"=#btME*~STRYK']);
  warn "------------\nDATABASE\n-------------\n";
  $self->_database;
  warn "------------\nPLUGINS\n-------------\n";
  $self->_plugins;
  warn "------------\nROUTES\n-------------\n";
  $self->_routes;
  warn "------------\nDONE\n-------------\n";
}


1;
