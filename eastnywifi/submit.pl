#!/usr/bin/perl
#
use strict;
use warnings;

use URI::Escape;
use HTML::Entities;
use HTTP::Request;
#use LWP::Debug qw(+ +conns);
#use LWP::Debug qw(+); ??
use LWP::UserAgent;
use JSON;
use Data::Dumper;
use DateTime;
use DateTime::Format::Strptime;

#  
#
#sub LWP::UserAgent::redirect_ok {
#  print "LWP::UserAgent::redirect_ok\n";
#  my ($self, $request) = @_;
#  $request->method("GET"),$request->content("") if $request->method eq "POST";
#  1;
#}

sub printWanStatus($) {
	no warnings;
	my $json = shift;
	foreach my $k (sort keys %$json) {
		if ($#{ $json->{$k}->{'interfaces'} } eq -1) {
			print "status $k: down\n";
		} else {
			printf "status $k: %s ifname %s\n", ($json->{$k}->{'up'}) ? "up": "down", $json->{$k}->{'interfaces'}->[0]->{'ifname'};
		}
	}
}


sub  ensureWanEnabled()
{
	my $cmd = 'ssh -i /home/nathaniel/.ssh/home.pem root@192.168.1.1 ';
	#	'uci set wireless.@wifi-iface[0].disabled=0'
	#open(CMD, 'ssh -i /home/nathaniel/.ssh/home.pem root@192.168.1.1 uci set wireless.@wifi-iface[3].disabled=0 |');
	#'; uci commit; wifi reload |');

	open(CMD, 'ssh -i /home/nathaniel/.ssh/home.pem root@192.168.1.1 wifi status |');
	my $slurp = $/;
	$/ = undef;
	my $status = <CMD>;
	my $w = decode_json($status);
	print "wan status: :\n";
	printWanStatus($w);

	my @cmds;
	my $uciname = {
		'radio0' => 'wifinet2',
		'radio1' => 'default_radio1',
#		'radio2' => 'radio2_ap',
	};

	foreach my $k (sort keys %$w) {
		my $r = $w->{$k};
	#  the radio "device" can show as up in wifi status without an associated interface (which is down)
	#
		if (not $r->{'up'} or $#{ $r->{'interfaces'} } eq -1) {
			my $un = $uciname->{$k};
			push @cmds, "uci set wireless.$un.disabled=0";
		}
	}

	#  put uci changes into action (wifi util is just a wrapper around ubus with many munged calls
	#    in the end, ubus takes args and a json message, yet fortunately for this purpose we need no message
	#
	if ($#cmds > -1) {
	  $cmd .= "'" .join(';', @cmds, 'ubus call network reload') . "' |";
	  print "$cmd\n";
	  open(CMD, $cmd);
	}
	$/ = $slurp;
}

#open(CMD, "sudo ip r |");
sub getGateway()
{
	my $gw = undef;
	open(CMD, 'ssh -i /home/nathaniel/.ssh/home.pem root@192.168.1.1 ip r |');
	while (<CMD>) {
	  chomp;
	  if ($_ =~ /default via (?<ip>[\d\.]+)/) {
	    $gw= "$+{ip}";
	  }
	}
	return $gw
}

sub getPortalToken(;$)
{
	my $args = shift || {};
	my $endpoint = $args->{'endpoint'} || "index.html";
	my $token = undef;
	my $host = $args->{'host'} || getGateway();
	my $ua = $args->{'ua'} || LWP::UserAgent->new;

	my $r = {};

	#my $req = HTTP::Request->new(POST => 'http://search.cpan.org/search');
	my $req = HTTP::Request->new(GET => "http://$host/$endpoint");
	my $res = $ua->request($req);

	#  followed $ua->max_redirect redirects yet ended still on a redirect
	#    not sure if it's an edge case but here it means we already have a server session
	#
	if ($res->is_redirect) {
		return $r;
	}

	# Check the outcome of the response
	if ($res->is_success) {
		if ($res->content =~ /form method=\"get\" action=\"(?<action>.*?)\"/) {
			$r->{'action'} = $+{'action'};
		}
		if ($res->content =~ /input name=\"tok\" value=\"(?<tok>.*?)\"/) {
			$r->{'token'} = $+{'tok'};
		}
		if ($res->content =~ /input name=\"redir\" value=\"(?<redir>.*?)\"/) {
			$r->{'redir'} = $+{'redir'};
		}
	}
	else {
		print $res->status_line, "\n";
		print $res->content;
	}
	return $r;
}

sub clickContinue($)
{
	my $args = shift || {};
	my $ua = $args->{'ua'} || LWP::UserAgent->new;
	if (exists $args->{'token'}) {

		#  just because east ny wifi regurgitates whatever host originally was used in the redir,
		#   they do specify a redirect as a form input type
		#    part of the standard? others might use this 
		#
		my $url = decode_entities($args->{'redir'}) . decode_entities($args->{'action'});
		#
		my $req = HTTP::Request->new(POST => "$url");
		$req->content_type('application/x-www-form-urlencoded');
		$req->content("tok=".decode_entities($args->{'token'}));

		print $req->as_string;

		my $res = $ua->request($req);

		if ($res->is_success) {
			print $res->content;
		} else {
			print $res->status_line, "\n";
		}
	} else {
		print "no token, skipping post.  should already have a server side session\n";
	}
}

#require LWP::ConsoleLogger::Everywhere;
#
my $begin = DateTime->now;
$begin->set_time_zone('local');

#  for the cron logs
#
print "$begin\n";

my $ua = LWP::UserAgent->new;
$ua->max_redirect(5);
$ua->agent("Mozilla/5.0 (Windows NT 6.1)");

my $action = "";#"&#47;";
my $tok = "";#"&#54;&#56;&#99;&#57;&#98;&#50;&#99;&#102;";
my $redir = "";#"&#104;&#116;&#116;&#112;&#58;&#47;&#47;&#49;&#48;&#46;&#50;&#53;&#53;&#46;&#49;&#56;&#56;&#46;&#49;&#47;";
#  openWrt has quirky behavior
#    there is some kind of gremlin daemon (monitor?) that will disable interfaces at will
#    so i spent a few hours figuring out how to enable them via cli
#
ensureWanEnabled();
my $tuple = getPortalToken({ua => $ua, endpoint => "generate_204"});
clickContinue($tuple);

