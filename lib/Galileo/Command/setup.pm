package Galileo::Command::setup;
use Mojo::Base 'Mojolicious::Command';

use Mojolicious::Command::daemon;

use Mojolicious::Routes;
use Mojo::JSON 'j';
use Mojo::Util 'spurt';

use Galileo::DB::Deploy;

has description => "Configure your Galileo CMS via a web interface\n";

sub run {
  my ($self, @args) = @_;

  my $app = $self->app;

  my $r = Mojolicious::Routes->new;
  $app->routes($r); # remove all routes

  push @{ $app->renderer->classes }, __PACKAGE__;

  $app->helper( dh => sub {
    my $self = shift;
    state $dh = Galileo::DB::Deploy->new( schema => $self->app->schema );
    $dh;
  });

  $app->helper( 'control_group' => sub {
    my $self = shift;
    my $contents = pop;
    my %args = @_;
 
    $self->include( #TODO use render_to_string when Mojo 5.00 is required
      template => 'setup/control_group',
      'control_group.contents' => ref $contents ? $contents->() : $contents,
      'control_group.label' => $args{label} || '',
      'control_group.for'   => $args{for}   || '',
    );
  });

  $r->any( '/' => 'setup/welcome' );
  $r->any( '/configure' => 'setup/configure' );
  $r->any( '/store_config' => sub {
    my $self = shift;
    my @params = sort $self->param;

    # map JSON keys to Perl data
    my %params = map { $_ => scalar $self->param($_) } @params;
    foreach my $key ( qw/extra_css extra_js extra_static_paths secrets db_options pagedown_extra_options/ ) {
      $params{$key} = j($params{$key});
    }

    spurt $self->dumper(\%params), $self->app->config_file;
  
    $self->app->load_config;
    $self->humane_flash( 'Configuration saved' );
    $self->redirect_to('/');
  });

  $r->any( '/database' => sub {
    my $self = shift;

    my $dh = $self->dh;
    my $schema = $dh->schema;

    my $available = $schema->schema_version;

    # Nothing installed
    unless ( $dh->has_admin_user ) {
      return $self->render( 'setup/database' );
    }

    # Something is installed, check for a version
    my $installed = $dh->installed_version || $dh->setup_unversioned;

    # Do nothing if version is current
    if ( $installed == $available ) {
      $self->flash( 'galileo.message' => 'Database schema is current' );
    } else {
      $self->flash( 'galileo.message' => "Upgrade database $installed -> $available" );
      $dh->do_upgrade;
    }

    $self->redirect_to('finish');
  });

  $r->any( '/database_install' => sub {
    my $self = shift;
    my $pw1 = $self->param('pw1');
    my $pw2 = $self->param('pw2');
    unless ( $pw1 eq $pw2 ) {
      $self->humane_flash( q{Passwords don't match!} );
      return $self->redirect_to('database');
    }

    my $dh = $self->dh;
    my $user = $self->param('user');
    my $full = $self->param('full');

    eval { $dh->schema->deploy };
    eval { $dh->do_install };
    eval { $dh->inject_sample_data($user, $pw1, $full) };
    if ($@) {
      my $error = "$@";
      chomp $error;
      $self->humane_flash( $error );
      return $self->redirect_to('database');
    }

    $self->flash( 'galileo.message' => 'Database has been setup' );
    $self->redirect_to('finish');
  });

  $r->any('/finish' => sub {
    my $self = shift;
    my $message = $self->flash( 'galileo.message' );

    # check that an admin user exists
    if ( $self->app->dh->has_admin_user ) {
      $self->stash( 'galileo.success' => 1 );
      $self->stash( 'galileo.message' => $message );
    } else {
      $self->stash( 'galileo.success' => 0 );
      $self->stash( 
        'galileo.message' =>
        'It does not appear that your database is setup, please rerun the setup utility'
      );
    }

    $self->humane_stash( 'Goodbye' );
    $self->render('setup/finish');
    $self->tx->on( finish => sub { exit } );
  });

  $self->Mojolicious::Command::daemon::run(@args);
}

1;

