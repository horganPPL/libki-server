package Libki::Controller::API::Public::Reservations;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

Libki::Controller::API::Public::Reservations - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 create

=cut

sub create : Local : Args(0) {
    my ( $self, $c ) = @_;

    my $username  = $c->request->params->{'username'};
    my $password  = $c->request->params->{'password'};
    my $client_id = $c->request->params->{'id'};

    my $user =
      $c->model('DB::User')->search( { username => $username } )->next();

    if (
        $c->authenticate(
            {
                username => $username,
                password => $password
            }
        )
      )
    {

        if ( $c->model('DB::Reservation')
            ->search( { user_id => $user->id(), client_id => $client_id } )
            ->next() )
        {
            $c->stash(
                'success' => 0,
                'reason'  => 'CLIENT_USER_ALREADY_RESERVED'
            );
        }
        elsif (
            $c->model('DB::Reservation')->search( { client_id => $client_id } )
            ->next() )
        {
            $c->stash( 'success' => 0, 'reason' => 'CLIENT_ALREADY_RESERVED' );
        }
        elsif (
            $c->model('DB::Reservation')->search( { user_id => $user->id() } )
            ->next() )
        {
            $c->stash( 'success' => 0, 'reason' => 'USER_ALREADY_RESERVED' );
        }
        else {
            if ( $c->model('DB::Reservation')
                ->create( { user_id => $user->id(), client_id => $client_id } )
              )
            {
                $c->stash( 'success' => 1 );
            }
            else {
                $c->stash( 'success' => 0, 'reason' => 'UNKNOWN' );
            }
        }
    }

    $c->logout();

    $c->forward( $c->view('JSON') );
}

=head2 delete

=cut

sub delete : Local : Args(0) {
    my ( $self, $c ) = @_;

    my $password  = $c->request->params->{'password'};
    my $client_id = $c->request->params->{'id'};

    my $user = $c->model('DB::Client')->find($client_id)->reservation->user;

    if (
        $c->authenticate(
            {
                username => $user->username,
                password => $password
            }
        )
      )
    {

        if ( $c->model('DB::Reservation')
            ->search( { user_id => $user->id(), client_id => $client_id } )
            ->next()->delete() )
        {
            $c->stash( 'success' => 1, );
        }
        else {
            $c->stash( 'success' => 0, 'reason' => 'UNKNOWN' );
        }
    }

    $c->logout();

    $c->forward( $c->view('JSON') );
}

=head1 AUTHOR

libki,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
