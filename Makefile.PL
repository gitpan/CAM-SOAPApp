use ExtUtils::MakeMaker qw(WriteMakefile prompt);

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
if (prompt("Do you want to enable these tests?", "y") =~ /^y/i) {
   open(ENABLED, ">t/ENABLED") || die "Can't enable: $!";
   close(ENABLED);
}

WriteMakefile(
              'NAME'		=> 'CAM::SOAPApp',
              'VERSION_FROM'	=> 'lib/CAM/SOAPApp.pm',
              'PREREQ_PM'		=> {
                 'CAM::App'        => 0.08,
                 'SOAP::Lite'      => 0.55,
              },
              'PL_FILES'        => {},
              ($] >= 5.005 ?
               (ABSTRACT_FROM => 'lib/CAM/SOAPApp.pm',
                AUTHOR     => 'Clotho Advanced Media <cpan@clotho.com>') : ()),
              );
