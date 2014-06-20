package Tools::Boxcar2;

use strict;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Mask;
use Multicast;
# --------------------------------------
use Encode qw(decode encode);
use LWP::UserAgent;
# --------------------------------------
sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{source}   = __PACKAGE__;
    $this->{encoding} = undef;
    $this->{token}    = undef;
    $this->{sound}    = undef;
    $this->{keyword}  = undef;
    $this->{channel}  = undef;
    $this->_init;
    return $this;
}

sub _init {
    my $this = shift;

    $this->{encoding} = $this->config->encoding || 'UTF-8';
    $this->{token}    = $this->config->token;
    $this->{sound}    = $this->config->sound;
    foreach ($this->config->keyword('all')) {
	s/(,)\s+/$1/g;
	my @keywords = split(/,/);
	foreach my $kw (@keywords) {
	    push @{$this->{keyword}}, decode($this->{encoding}, $kw);
	}
    }
    foreach ($this->config->channel_keyword('all')) {
	s/(,)\s+/$1/g;
	s/\s+(\|)\s+/$1/g;
	my ($channels, $keywords) = split(/\s+/);
	foreach my $ch (split(/,/, $channels)) {
	    $ch = decode($this->{encoding}, $ch);
	    $this->{channel}{$ch} = decode($this->{encoding}, $keywords);
	}
    }
}

############################################################

sub message_arrived {
    my ($this, $msg, $sender) = @_;
    my @result = ($msg);

    if ($msg->command eq 'PRIVMSG') {
	my ($sender_nick) = $msg->prefix =~ /(.+)\!/;
	if (!$sender_nick) {
	    if ($sender->isa('IrcIO::Client')) {
		$sender_nick = $sender->{nick};
	    } else {
		$sender_nick = $sender->{current_nick};
	    }
	}

    	my (undef, undef, undef, $reply_anywhere, $get_full_ch_name)
	    = Auto::Utils::generate_reply_closures($msg, $sender, \@result);
	my $channel = decode($this->{encoding}, $msg->param(0));
	my $line    = decode($this->{encoding}, $msg->param(1));

	my $flag = 0;
	foreach my $kw (@{$this->{keyword}}) {
	    if ($line =~ /$kw/i) {
		Boxcar2($this, $channel, $sender_nick, $line);
		$flag++;
		last;
	    }
	}
	if (! $flag) {
	    foreach my $ch (keys %{$this->{channel}}) {
		if (lc($channel) eq lc($ch) and $line =~ /$this->{channel}{$ch}/i) {
		    Boxcar($this, $channel, $sender_nick, $line);
		    last;
		}
	    }
	}
    }
    @result;
}

sub Boxcar2 {
    my ($this, $channel, $nick, $message) = @_;

    $channel = encode('UTF-8', $channel);
    $message = encode('UTF-8', $message);

    # omit for TIG typable map
    $message =~ s/\s+\x3.*$//;
    $message =~ s/[\x01-\x1F]//g;

    my %formdata = (
	user_credentials => $this->{token},
	'notification[title]' => "$channel $nick",
	'notification[long_message]' => $message,
	'notification[sound]' => $this->{sound} || 'clanging',
	'notification[source_name]' => $this->{source},
	);
    LWP::UserAgent->new(timeout => 10)->post(
	'https://new.boxcar.io/api/notifications',
	\%formdata);
}

1;