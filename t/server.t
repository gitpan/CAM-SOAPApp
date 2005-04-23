#!/usr/bin/perl -w

use warnings;
use strict;
use lib qw(./t);

BEGIN
{ 
   $| = 1;
   use Test::More tests => 8;
   use_ok("CAM::SOAPApp");
   use_ok("Example::Server");
}

my $PORT = 9674;
my $TIMEOUT = 5; # seconds

SKIP: {

   if (! -f "t/ENABLED")
   {
      skip("User elected to skip tests.",
           # Hack: get the number of tests we expect, skip all but one
           # This hack relies on the soliton nature of Test::Builder
           Test::Builder->new()->expected_tests() - 
           Test::Builder->new()->current_test());
   }

   my $child = fork();
   if ($child)
   {
      # We're the parent, continue below
   }
   elsif (defined $child)
   {
      
      # We're in the child.  Launch the server and continue until parent
      # kills us, or we time out.
      
      $SIG{ALRM} = sub {exit(1)};
      alarm($TIMEOUT);
      &runServer();
      exit(0);
   }
   else
   {
      die "Fork error...\n";
   }
   
   pass("forked off a server daemon process, waiting 2 seconds");
   
   sleep(2); # wait for server
   
   require IO::Socket;
   my $s = IO::Socket::INET->new(PeerAddr => "localhost:$PORT",
                                 Timeout  => 10);
   ok($s, "server is running");
   close($s) if ($s);

   my $som;
   my $result;
   my $client = SOAP::Lite
       -> uri("http://localhost/Example/Server")
       -> proxy("http://localhost:$PORT/")
       -> on_fault( sub { my ($soap, $fault) = @_;
                          $main::error = ref $fault ? $fault->faultcode() : "Unknown"; } );

   call($client, "isLeapYear", [             ], [0, "SOAP-ENV:NoYear"], "Fault: NoYear");
   call($client, "isLeapYear", [year => "doh"], [0, "SOAP-ENV:BadYear"],"Fault: BadYear");
   call($client, "isLeapYear", [year => 1996 ], [1, 1], "1996 is a leap year");
   call($client, "isLeapYear", [year => 2003 ], [1, 0], "2003 is not a leap year");

   # Stop the server
   $client->call("quit");
   kill(9, $child); # just in case
}

exit(0);

sub call
{
   my $client = shift;
   my $method = shift;
   my $args = shift;
   my $expect = shift;
   my $desc = shift;

   my @args = ();
   for (my $i=0; $i<@$args; $i+=2)
   {
      push @args, SOAP::Data->name($args->[$i], $args->[$i+1]);
   }
   
   $main::error = '';
   my $som = $client->call($method, @args);
   if ($expect->[0])
   {
      if (ref $som)
      {
         is($som->result(), $expect->[1], $desc);
      }
      else
      {
         fail($desc);
      }
   }
   else
   {
      if (ref $som)
      {
         fail($desc);
      }
      else
      {
         is($som, $expect->[1], $desc);
      }
   }
}

sub runServer
{
   eval "use SOAP::Transport::HTTP";
   SOAP::Transport::HTTP::Daemon
       -> new(LocalAddr => 'localhost', LocalPort => $PORT)
       -> dispatch_to('Example::Server')
       #-> on_fault( sub {} )
       -> handle;
}
