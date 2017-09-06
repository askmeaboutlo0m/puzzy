package Puzzy::Controller::Auth;
use Mojo::Base 'Mojolicious::Controller';
use 5.018;
use Unicode::Normalize qw(NFC);


sub check {
  my ($self) = @_;

  if ($self->is_user_authenticated) {
    return 1;
  }
  else {
    $self->render('forbidden', status => 403, format => 'html');
    return 0;
  }
}


sub log_in {
  my ($self) = @_;
  my $error;

  if ($self->req->method eq 'POST') {
    my $val = $self->validation;
    $val->csrf_protect;
    $val->required('name', 'trim')->like(qr/\S/);
    $val->required('pass', 'trim')->like(qr/\S/);

    if ($val->has_error) {
      $error = 1;
    }
    else {
      my $name = fc NFC($val->param('name'));
      my $pass =    NFC($val->param('pass'));
      if ($self->authenticate($name, $pass)) {
        return $self->redirect_to($self->param('want') || '/W/hatGet');
      }
      else {
        $error = 1;
      }
    }
  }

  $self->render('login', login_error => $error);
}


sub log_out {
  my ($self) = @_;

  return $self->redirect_to('/login') unless $self->is_user_authenticated;

  if ($self->req->method eq 'POST' && !$self->validation->csrf_protect->has_error) {
    $self->logout;
    return $self->redirect_to('/login');
  }

  $self->render('logout');
}


1;
