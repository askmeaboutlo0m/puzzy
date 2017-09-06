package Puzzy::Controller::Whatget;
use Mojo::Base 'Mojolicious::Controller';
use 5.018;

use constant CREATE          => 1;
use constant DELETE          => 2;
use constant RESTORE         => 3;
use constant UPDATE_NAME     => 4;
use constant UPDATE_CATEGORY => 5;


sub _read_item {
  my ($self, $id, $db) = @_;
  $db ||= $self->db;
  return $db->select(items => [qw(id name category)], {id => $id})->hash;
}

sub _read_items {
  my ($self, $page, $categories) = @_;

  my $where = {
    deleted => 0,
    page    => $page,
  };

  if ($categories && @$categories) {
    $where->{category} = $categories;
  }

  return $self->db->select(
    items => [qw(id name category)], $where, {-asc => 'id'}
  );
}

sub _read_history {
  my ($self, $page) = @_;
  return $self->db->query('SELECT   h.timestamp, h.info, h.action,
                                    i.name, i.category
                           FROM     history h
                           JOIN     items i
                           ON       h.item = i.id
                           WHERE    i.page = ?
                           ORDER BY h.id DESC', $page);
}


sub _create_history {
  my ($self, $db, $id, $action, $info) = @_;
  $db->insert(history => {
    item      => $id,
    action    => $action,
    info      => $info,
    timestamp => time,
  });
}

sub _create_item {
  my ($self, $name, $category, $page) = @_;
  my $db = $self->db;
  my $tx = $db->begin;

  $db->insert(items => {
    name     => $name,
    category => $category,
    page     => $page,
  });

  my $id = $db->query('SELECT MAX(id) AS id FROM items WHERE page = ?', $page)
              ->hash->{id};

  $self->_create_history($db, $id, CREATE);

  $tx->commit;
  return $id;
}


sub _update {
  my ($self, $db, $item, $key, $value) = @_;

  state $action = {name => UPDATE_NAME, category => UPDATE_CATEGORY};

  if (defined $value) {
    $db->update(items => {$key => $value}, {id => $item->{id}});
    $self->_create_history($db, $item->{id}, $action->{$key}, $item->{$key});
    $item->{$key} = $value;
  }
}

sub _update_item {
  my ($self, $id, $name, $category) = @_;
  my $db = $self->db;
  my $tx = $db->begin;

  my $item = $self->_read_item($id, $db);
  if ($item) {
    $self->_update($db, $item, name     => $name    );
    $self->_update($db, $item, category => $category);
  }

  $tx->commit;
  return $item;
}

sub _delete_item {
  my ($self, $id) = @_;
  my $db = $self->db;
  my $tx = $db->begin;

  my $rows = $db->update(
    items => {deleted => 1}, {id => $id, deleted => 0}
  )->rows;

  if ($rows) {
    $self->_create_history($db, $id, DELETE);
  }

  $tx->commit;
  return $rows;
}

sub _restore_item {
  my ($self, $id) = @_;
  my $db = $self->db;
  my $tx = $db->begin;

  my $rows = $db->update(
    items => {deleted => 0}, {id => $id, deleted => {'!=', 0}}
  )->rows;

  if ($rows) {
    $self->_create_history($db, $id, RESTORE);
  }

  $tx->commit;
  return $rows;
}


sub _undo_create {
  my ($self, $db, $id) = @_;
  $db->delete(items => {id => $id});
}

sub _undo_delete {
  my ($self, $db, $id) = @_;
  $db->update(items => {deleted => 0}, {id => $id});
}

sub _undo_restore {
  my ($self, $db, $id) = @_;
  $db->update(items => {deleted => 1}, {id => $id});
}

sub _undo_update_name {
  my ($self, $db, $id, $info) = @_;
  $db->update(items => {name => $info}, {id => $id});
}

sub _undo_update_category {
  my ($self, $db, $id, $info) = @_;
  $db->update(items => {category => $info}, {id => $id});
}

sub _undo {
  my ($self, $page) = @_;

  state $handlers = {
    CREATE,          '_undo_create',
    DELETE,          '_undo_delete',
    RESTORE,         '_undo_restore',
    UPDATE_NAME,     '_undo_update_name',
    UPDATE_CATEGORY, '_undo_update_category',
  };

  my $db   = $self->db;
  my $tx   = $db->begin;
  my $undo = $db->query('SELECT   h.id, h.timestamp, h.item, h.action, h.info
                         FROM     history h
                         JOIN     items   i
                         ON       h.item = i.id
                         WHERE    i.page = ?
                         ORDER BY h.id DESC
                         LIMIT 1', $page)->hash;

  if ($undo) {
    my $method = $handlers->{$undo->{action}};
    $self->$method($db, @{$undo}{'item', 'info'});
    $db->delete(history => {id => $undo->{id}});
  }

  $tx->commit;
  return $undo;
}


sub _page {
  my $self = shift;
  my $page = $self->db->select(
    pages => ['id'], {page_name => $self->param('page')}
  )->hash;

  if ($page) {
    return $page->{id};
  }
  else {
    $self->render(status => 404, format => 'html');
    return undef;
  }
}


sub index {
  shift->render('whatget');
}

sub index_txt {
  my $self  = shift;
  my $page  = $self->_page or return;
  my $items = $self->_read_items($page, $self->every_param('category'));

  my %categories;
  while (my $item = $items->hash) {
    push @{$categories{$item->{category}}}, $item->{name};
  }

  $self->render('whatget',
    categories => \%categories,
    format     => 'txt',
    title      => 'W' . $self->param('page'),
  );
}


sub get_items {
  my $self = shift;
  my $page = $self->_page or return;
  return $self->render(json => $self->_read_items($page)->hashes);
}

sub get_history {
  my $self = shift;
  my $page = $self->_page or return;
  return $self->render(json => $self->_read_history($page)->hashes);
}


sub post_item {
  my $self = shift;
  my $page = $self->_page or return;
  my $val  = $self->validation;

  $val->input($self->req->json);
  $val->required('name',     'trim')->like(qr/\S/);
  $val->required('category', 'trim')->like(qr/\S/);

  if ($val->has_error) {
    return $self->render(status => 400, json => $val->failed);
  }

  my $id = $self->_create_item($val->param('name'), $val->param('category'), $page);
  return $self->render(status => 201, json => $self->_read_item($id));
}

sub patch_item {
  my $self = shift;
  my $val  = $self->validation;

  $val->input($self->req->json);
  $val->optional('name',     'trim')->like(qr/\S/);
  $val->optional('category', 'trim')->like(qr/\S/);

  if ($val->has_error) {
    return $self->render(status => 400, json => $val->failed);
  }

  my $id   = $self->param('id');
  my $item = $self->_update_item($id, $val->param('name'), $val->param('category'));

  if ($item) {
    return $self->render(json => $item);
  }
  else {
    return $self->render(status => 404);
  }
}

sub delete_item {
  my $self = shift;
  my $rows = $self->_delete_item($self->param('id'));
  return $self->render(json => {deleted => $rows});
}

sub restore_item {
  my $self = shift;
  my $rows = $self->_restore_item($self->param('id'));
  return $self->render(json => {restored => $rows});
}


sub undo {
  my $self = shift;
  my $page = $self->_page or return;
  return $self->render(json => {undo => $self->_undo($page)});
};


1;
