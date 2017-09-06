package Puzzy::Controller::Annotation;
use Mojo::Base 'Mojolicious::Controller';
use 5.018;
use List::Util qw(max min);
use Mojo::Util qw(xml_escape);


my %types = (
  c => ['content',  [17,  100, 50]],
  f => ['form',     [40,  100, 50]],
  g => ['grammar',  [0,   100, 50]],
  s => ['spelling', [240, 100, 50]],
  t => ['tense',    [120, 100, 50]],
);


sub _colorize {
  my ($h, $s, $l) = @{shift()};
  my $ml = max(0, min(100, $l + shift));
  return "$h, $s%, $ml%";
}

sub _make_annotation {
  my ($text, $type, $author, $note) = @_;

  my $tip = '';
  my $box = '';
  my $key = lc substr $type || '', 0, 1;

  if (exists $types{$key}) {
    ($type, my $hsl) = @{$types{$key}};
    $tip = qq(style="color:hsl(${\_colorize($hsl, -20)});");
    $box = qq(style="background:hsla(${\_colorize($hsl, 35)}, 0.95);");
  }

  if ($author || $type) {
    $note .= '<br><small>';
    $note .= "<strong>$author</strong> " if $author;
    $note .= "($type)" if $type;
    $note .= '</small>';
  }

  return qq(<a class="tooltip" $tip>$text<span $box>$note</span></a>);
}


sub _annotate {
  my $text = xml_escape(shift);

  $text =~ s/-{3,}/<hr>/g;
  $text =~ s{
    # original text in square brackets
    \[
      ([^\]]*)
    \]
    \s*
    # annotation stuff in parens
    \(
      # maybe a type| or type@author| prefix
      (?:
        ([^)|@]*)
        (?:@([^)|]*))?
        \|
      )?
      # the actual annotation
      ([^)]*)
    \)
  }{_make_annotation($1, $2, $3, $4)}gex;

  return $text;
}


sub form {
  shift->render('annotate', title => 'Annotate');
}

sub build {
  my ($self) = @_;

  if ($self->param('download')) {
    $self->res->headers->content_disposition('attachment; filename=annotated.html');
  }

  $self->render('annotated',
    title     => $self->param('title'),
    annotated => _annotate($self->param('text')),
  );
}


1;
