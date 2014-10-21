package Galileo::Command::setup;
use Mojo::Base 'Mojolicious::Command';

use Term::Prompt qw/prompt/;

has description => "Deploy/upgrade the database for your Galileo CMS application.\n";
has usage       => "usage: $0 setup\n";

use Galileo::DB::Deploy;

sub run {
  my ($self) = @_;

  my $dh = Galileo::DB::Deploy->new( schema => $self->app->schema );
  $self->deploy_or_upgrade_schema( $dh );

  say "Run 'galileo daemon' to start the server.";
}

sub deploy_or_upgrade_schema {
  my $self = shift;
  my $dh = shift;
  my $schema = $dh->schema;

  my $available = $schema->schema_version;

  # Nothing installed
  unless ( eval { $schema->resultset('User')->first } ) {
    say "Installing database version: $available";
    $self->install_schema( $dh );
    return;
  }

  # Something is installed, check for a version
  my $installed = $dh->installed_version || $dh->setup_unversioned;

  # Do nothing if version is current
  if ( $installed == $available ) {
    say "Database schema is current";
    return;
  }

  say "Upgrade database $installed -> $available";

  $dh->do_upgrade;
}

sub install_schema {
  my $self = shift;
  my $dh = shift;

  my ($user, $full, $pass) = $self->prompt_for_user_info;

  $dh->do_install;
  $dh->inject_sample_data($user, $pass, $full);
}

sub prompt_for_user_info {

  my $self = shift;

  my $user = prompt('x', 'Admin Username: ', '', '');
  my $full = prompt('x', 'Admin Full Name: ', '', '');
  my $pass1 = prompt('p', 'Admin Password: ', '', '');
  print "\n";

  #TODO check for acceptable password

  my $pass2 = prompt('p', 'Repeat Admin Password: ', '', '');
  print "\n";

  unless ($pass1 eq $pass2) {
    die "Passwords do not match";
  }

  return ( $user, $full, $pass1 );
}

1;
