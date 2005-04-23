package CAM::SOAPApp;

=head1 NAME

CAM::SOAPApp - SOAP application framework

=head1 LICENSE

Copyright 2005 Clotho Advanced Media, Inc., <cpan@clotho.com>

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SYNOPSIS

Do NOT subclass from this module to create your SOAP methods!  That
would make a big security hole.  Instead, write your application like
this example:

  use CAM::SOAPApp;
  SOAP::Transport::HTTP::CGI
    -> dispatch_to('My::Class')
    -> handle;
  
  package My::Class;
  our @ISA = qw(SOAP::Server::Parameters);
  sub isLeapYear {
     my $pkg = shift;
     my $app = CAM::SOAPApp->new(soapdata => \@_);
     unless ($app) {
        CAM::SOAPApp->error("Internal", "Failed to initialize the SOAP app");
     }
     my %data = $app->getSOAPData();
     unless (defined $data{year}) {
        $app->error("NoYear", "No year specified in the query");
     }
     unless ($data{year} =~ /^\d+$/) {
        $app->error("BadYear", "The year must be an integer");
     }
     my $leapyear = ($data{year} % 4 == 0 && 
                     ($data{year} % 100 != 0 || 
                      $data{year} % 400 == 0));
     return $app->response(leapyear => $leapyear ? 1 : 0);
  }

=head1 DESCRIPTION

CAM::SOAPApp is a framework to assist SOAP applications.  This package
abstracts away a lot of the tedious interaction with SOAP and the
application configuration state.  CAM::SOAPApp is a subclass of
CAM::App and therefore inherits all of its handy features.

When you create a class to hold your SOAP methods, that class should
be a subclass of SOAP::Server::Parameters.  It should NOT be a
subclass of CAM::SOAPApp.  If you were to do the latter, then all of
the CAM::App and CAM::SOAPApp methods would be exposed as SOAP
methods, which would be a big security hole, so don't make that
mistake.

=cut

#--------------------------------#

require 5.005_62;
use strict;
use warnings;
use SOAP::Lite;
use CAM::App;

our @ISA = qw(CAM::App);
our $VERSION = '1.05';

#--------------------------------#

=head1 OPTIONS

When loading this module, there are a few different options that can
be selected.  These can be mixed and matched as desired.

=over 4

=item use CAM::SOAPApp;

This initializes SOAPApp with all of the default SOAP::Lite options.

=item use CAM::SOAPApp (lenient => 1);

This tweaks some SOAP::Lite and environment variables to make the
server work with SOAP-challenged clients.  These tweaks specifically
enable HTTP::CGI and HTTP::Daemon modes for client environments which
don't offer full control over their HTTP channel (like Flash and Apple
Sherlock 3).

Specifically, the tweaks include the following:

=over 4

=item Content-Type

Sets Content-Type to C<text/xml> if it is not set or is set
incorrectly.

=item SOAPAction

Replaces missing SOAPAction header fields with "".

=item Charset

Turns off charset output for the Content-Type (i.e. "text/xml" instead
of "text/xml; charset=utf-8").

=item HTTP 500

Outputs HTTP 200 instead of HTTP 500 for faults.

=item XML trailing character

Adds a trailing '>' to the XML if one is missing.  This is to correct
a bug in the way Safari 1.0 posts XML from Flash.

=back

=item use CAM::SOAPApp (handle => PACKAGE);

(Experimental!) Kick off the SOAP handler automatically.  This runs
the following code immediately:

  SOAP::Transport::HTTP::CGI
    -> dispatch_to(PACKAGE)
    -> handle;

Note that you must load PACKAGE before this statement.

=back

=cut

sub import
{
   my $pkg = shift;
   while (@_ > 0)
   {
      my $key = shift;
      my $value = shift;
      if ($key =~ /^-?lenient$/i && $value)
      {
         ## No longer applicable.  This works fine with v0.60
         #if (!$CAM::SOAPApp::NO_SOAP_LITE_WARNING &&
         #    (!defined $SOAP::Lite::VERSION ||
         #     $SOAP::Lite::VERSION ne "0.55"))
         #{
         #   warn("SOAP::Lite version is not v0.55\n".
         #        "  $pkg lenient mode is optimized for SOAP::Lite v0.55.\n" .
         #        "  It has not been tested with other SOAP::Lite versions.\n".
         #        "  To silence this warning set\n".
         #        "     $CAM::SOAPApp::NO_SOAP_LITE_WARNING = 1;\n");
         #}

         ## Hack to repair content-type for clients who send the wrong
         ## value or no value (notably the Apple Sherlock 3 interface
         ## and Flash)

         # This doesn't actually work for servers, but we'll include
         #it in case SOAP::Lite ever gets fixed.
         $SOAP::Constants::DO_NOT_CHECK_CONTENT_TYPE = 1;

         # CGI version
         unless ($ENV{CONTENT_TYPE} &&
                 ($ENV{CONTENT_TYPE} =~ /^text\/xml/ ||
                  $ENV{CONTENT_TYPE} =~ /^multipart\/(related|form-data)/))
         {
            $ENV{CONTENT_TYPE} = "text/xml";
         }

         # Daemon version
         *SOAP::Transport::HTTP::Daemon::request = sub
         {
            my $self = shift->new;
            if (@_)
            {
               $self->{_request} = shift;
               $self->{_request}->content_type("text/xml");
               return $self;
            }
            else
            {
               return $self->{_request};
            }
         };


         ## Allow missing SOAPAction header values (needed for Flash 6
         ## which cannot send arbitrary HTTP headers)

         # CGI version
         $ENV{HTTP_SOAPACTION} ||= '""';

         # Daemon version
         # Patch to return '""' instead of undef
         {
            no warnings; # quiet the redefined sub warning
            *SOAP::Server::action = sub
            {
               my $self = shift->new;
               @_ ? 
                   ($self->{_action} = shift, return $self) :
                   return $self->{_action} || '""';
            };
         }

         ## Repair for clients which are unhappy with response
         ## Content-Type values that are anything other than text/xml
         ## (like Flash 6)
         $SOAP::Constants::DO_NOT_USE_CHARSET = 1;
         
         ## Keep Apache from sending our faults as HTTP errors,
         ## which confuse dumb clients like Flash 6
         $SOAP::Constants::HTTP_ON_FAULT_CODE = 200;

         ## Override the request() method on HTTP::Server to fix the
         ## request if the browser has broken the XML (namely Safari
         ## v1.0 POSTing from Flash.  This is a hack that detects the
         ## missing ">" at the end of the XML request and appends it.
         require SOAP::Transport::HTTP;
         {
            no warnings; # quiet the redefined sub warning
            *SOAP::Transport::HTTP::Server::request = sub {
               my $self = shift->new;
               if (@_)
               {
                  $self->{_request} = shift;
                  if ($self->request->content =~ m|</[\w:-]+$|)
                  {
                     # close unclosed tag
                     $self->request->content($self->request->content . ">");
                  }
                  return $self;
               }
               else
               {
                  return $self->{_request};
               }
            };
         }
      }
      elsif ($key =~ /^-?handle$/i && $value)
      {
         require SOAP::Transport::HTTP;
         SOAP::Transport::HTTP::CGI
             -> dispatch_to($value)
             -> handle;
      }
   }
}

#--------------------------------#

=head1 METHODS

=over 4

=cut

#--------------------------------#

=item new soapdata => ARRAYREF

Create a new application instance.  The arguments passed to the SOAP
method should all be passed verbatim to this method as a reference,
less the package reference.  This should be like the following:

  sub myMethod {
     my $pkg = shift;
     my $app = CAM::SOAPApp->new(soapdata => \@_);
     ...
  }

=cut

sub new
{
   my $pkg = shift;
   my %args = (@_);

   my $self = $pkg->SUPER::new(cgi => undef, @_);

   my $soapdata = $args{soapdata};
   my $tail = $soapdata->[-1];
   if ($tail && ref($tail) && UNIVERSAL::isa($tail => 'SOAP::SOM'))
   {
      $self->{envelope} = pop @$soapdata;  # remove tail from the list
      # get the envelope data, or the empty set
      # Note: method() returns "" on no data, hence the "|| {}" below
      $self->{soapdata} = $self->{envelope}->method() || {};
   }
   else
   {
      if (@$soapdata % 2 != 0)
      {
         push @$soapdata, undef;  # even out the hash key/value pairs
      }
      $self->{soapdata} = {@$soapdata};
   }
   return $self;
}
#--------------------------------#

=item getSOAPData

Returns a hash of data passed to the application.  This is a massaged
version of the C<soapdata> array passed to new().

=cut

sub getSOAPData
{
   my $self = shift;
   return %{$self->{soapdata}};
}
#--------------------------------#

=item response KEY => VALUE, KEY => VALUE, ...

Prepare data to return from a SOAP method.  For example:

  sub myMethod {
     ...
     return $app->response(year => 2003, month => 3, date => 26);
  }

yields SOAP XML that looks like this (namespaces and data types
omitted for brevity):

  <Envelope>
    <Body>
      <myMethodResponse>
        <year>2003</year>
        <month>3</month>
        <date>26</date>
      </myMethodResponse>
    </Body>
  </Envelope>

=cut

sub response
{
   my $self = shift;
   return $self->encodeHash({@_});
}
#--------------------------------#

=item error

=item error FAULTCODE

=item error FAULTCODE, FAULTSTRING

=item error FAULTCODE, FAULTSTRING, KEY => VALUE, KEY => VALUE, ...

Emit a SOAP fault indicating a failure.  The C<faultcode> should be a
short, computer-readable string (like "Error" or "Denied" or "BadID").
The C<faultstring> should be a human-readable string that explains the
error.  Additional values are encapsulated as C<detail> fields for
optional context for the error.  The result of this method will look
like this (namespaces and data types omitted for brevity).

  <Envelope>
    <Body>
      <Fault>
        <faultcode>FAULTCODE</faultcode>
        <faultstring>FAULTSTRING</faultstring>
        <detail>
          <data>
            <KEY>VALUE</KEY>
            <KEY>VALUE</KEY>
            ...
          </data>
        <detail>
      </Fault>
    </Body>
  </Envelope>

=cut

sub error
{
   my $pkg_or_self = shift;
   my $code = shift || "Internal";
   my $string = shift || "Application Error";
   # rest of args handled below

   my $fault = SOAP::Fault->faultcode($code)->faultstring($string);
   if (@_ > 0)
   {
      if (@_ %2 != 0)
      {
         push @_, undef;  # even out the hash key/value pairs
      }
      $fault = $fault->faultdetail(SOAP::Data->name("data" => {@_}));
   }
   die $fault;
}
#--------------------------------#

=item encodeHash HASHREF

This is a helper function used by response() to encode hash data into
a SOAP-friendly array of key-value pairs that are easily transformed
into XML tags by SOAP::Lite.  You should generally use response()
instead of this function unless you have a good reason.

=cut

sub encodeHash
{
   my $pkg_or_self = shift;
   my $data = $_[0];

   return @_ unless($data && ref($data) && ref($data) eq "HASH");
   my @out;
   foreach my $key (sort keys %$data)
   {
      push @out, SOAP::Data->name($key => $data->{$key});
   }
   return @out;
}
#--------------------------------#

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>

Primary developer: Chris Dolan

