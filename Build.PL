use Module::Build;

open(FILE,"<t/server.t");
my ($PORT, $TIMEOUT);
while (<FILE>)
{
   /\$PORT = (\d+)/ && ($PORT = $1);
   /\$TIMEOUT = (\d+)/ && ($TIMEOUT = $1);
}
close(FILE);

print("Most of the tests require a live SOAP server.  We will start a\n" .
      "server on your computer listening on localhost port $PORT.\n" .
      "This server will will be killed at the end of the tests, or\n" .
      "after $TIMEOUT seconds, whichever comes first.\n" .
      "\n");

unlink("t/ENABLED");
if (Module::Build->prompt("Do you want to enable these tests?", "y") =~ /^y/i) {
   open(ENABLED, ">t/ENABLED") || die "Can't enable: $!";
   close(ENABLED);
}

Module::Build->new(
                   module_name => 'CAM::SOAPApp',
                   license => 'perl',
                   requires => {
                      'perl'                     => '5.6.0',
                      'CAM::App'                 => '0.08',
                      'SOAP::Lite'               => '0.55',
                   },
                   recommends => {
                      'LWP::UserAgent'           => '2.00',
                   },
                   build_requires => {
                      'Test::More'               => '0.01',
                      'IO::Socket'               => '1.00',
                      'HTTP::Daemon'             => '1.00',
                   },
                   )->create_build_script;
