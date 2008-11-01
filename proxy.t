#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy module.

###############################################################################

use warnings;
use strict;

use Test::More tests => 3;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new();

$t->write_file_expand('nginx.conf', <<'EOF');

master_process off;
daemon         off;

events {
    worker_connections  1024;
}

http {
    access_log    off;
    root          %%TESTDIR%%;

    client_body_temp_path  %%TESTDIR%%/client_body_temp;
    fastcgi_temp_path      %%TESTDIR%%/fastcgi_temp;
    proxy_temp_path        %%TESTDIR%%/proxy_temp;

    server {
        listen       localhost:8080;
        server_name  localhost;

        location / {
            proxy_pass http://localhost:8081;
            proxy_read_timeout 1s;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run();

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'proxy request');
like(http_get('/multi'), qr/AND-THIS/, 'proxy request with multiple packets');

unlike(http_head('/'), qr/SEE-THIS/, 'proxy head request');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
        	Proto => 'tcp',
		LocalHost => '127.0.0.1:8081',
        	Listen => 5,
        	Reuse => 1
	)
        	or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
        	$client->autoflush(1);

		my $headers = '';
		my $uri = '';

        	while (<$client>) {
			$headers .= $_;
                	last if (/^\x0d?\x0a?$/);
        	}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if ($uri eq '/') {
			print $client <<'EOF';
HTTP/1.1 200 OK
Connection: close

EOF
			print $client "TEST-OK-IF-YOU-SEE-THIS"
				unless $headers =~ /^HEAD/i;

		} elsif ($uri eq '/multi') {

        		print $client <<"EOF";
HTTP/1.1 200 OK
Connection: close

TEST-OK-IF-YOU-SEE-THIS
EOF

			select undef, undef, undef, 0.1;
			print $client 'AND-THIS';

		} else {

        		print $client <<"EOF";
HTTP/1.1 404 Not Found
Connection: close

Oops, '$uri' not found
EOF
		}

        	close $client;
	}
}

###############################################################################
