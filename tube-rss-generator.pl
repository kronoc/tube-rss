#!/usr/bin/perl -T

use strict;
#use warnings;
use Fcntl ":flock";
use LWP::UserAgent;
use HTML::TreeBuilder;
use XML::RSS;

my $ROOT_URL = 'http://www.tfl.gov.uk/tfl/livetravelnews/realtime/tube';
my $url="$ROOT_URL/default.html";
#my $url="http://conor.net/code/tube/tfl-sample.html";
my $FILE_LOCK='flock';
my $FEEDS_DIR='../../feeds/';
#my $FEEDS_DIR='./';
my $FILE_RSS="${FEEDS_DIR}rss/tube-gen.xml";
my $FILE_PSV="${FEEDS_DIR}cff/tube.cff";
#my $LINE_URL = "http://www.tfl.gov.uk/tfl/livetravelnews/realtime/tube/tube-<linename>-now.html";
my $CURRENT_TIME = time;
my $FORMATTED_TIME = getGMT();
my $TTL_MINUTES = 10;
my $TTL = ($TTL_MINUTES * 60);
#my $TTL = 1;
my $UA = LWP::UserAgent->new;
$UA->agent('Tubebot/1,0 http://conor.net/code/tube/');
$UA->from('info@conor.net');


my $doc = HTML::TreeBuilder->new;


if (-e $FILE_LOCK){
	#file lock exists - someone else is runnig the script
	#check the age of the lock file
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($FILE_LOCK);

	if(($CURRENT_TIME-$ctime) > $TTL){
		#locking file should not be here, delete it and run process
		&unlock;
		&run;
	}
	else{
		#process is running, or has run recently run it.
		#return the current rss file
		&getrss;
	}
}elsif  (-e $FILE_RSS){
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($FILE_RSS);
	if(($CURRENT_TIME-$ctime) > $TTL){
		#rss is too old
		&run;
	}else{
		&getrss;
	}
}else{
 &run;
}

sub getGMT {
	my $now_string = gmtime;
	my @timestring = split(/\ /, $now_string);
	my $formattedTime = "$timestring[0], $timestring[2] $timestring[1] $timestring[4] $timestring[3] GMT";
	return $formattedTime;
}


sub getrss {
	my @rss;
	open (RSS, $FILE_RSS) || die 'Cannot Open RSS File.\n';
	while( <RSS> ) {
		print;
	}
	#@rss = <RSS>;
	close (RSS);    
	#print "content-type: text/xml\n";
	#foreach (@rss) {print"$_\n";}
}

sub lock {
	open (LOCK, ">$FILE_LOCK");
	flock(LOCK, LOCK_EX);
	print LOCK ' ';
	flock(LOCK, LOCK_UN);
	close (LOCK);
}

sub unlock {
	unlink($FILE_LOCK);
}


sub get {
  my $geturl = shift;
  my $r = $UA->get($geturl);
  die "$url => " . $r->status_line if $r->is_error;
  return $r->content;
}


sub run {
&lock;

$doc->parse(get($url));

my @tubes;

my $dl = $doc->look_down(_tag => 'dl');
die 'No tube lines found\n' unless $dl;

my @dt = $dl->look_down(_tag => 'dt');
my @dd = $dl->look_down(_tag => 'dd');

my $counter=0;

foreach (@dt){
	my $tube;
	$tube->{safeline} = ($_->attr('class'));
	$tube->{line}=$_->as_text();
	$tube->{statusurl}=generateUrl($tube->{safeline});
	$tube->{lineurl}=$tube->{statusurl};
	my $status = $dd[$counter]->as_text();
	if ($status eq 'Good service'){
		$tube->{status}=$status;
		$tube->{details} = $tube->{status};
	}else{
		$tube->{status}=( $dd[$counter]->look_down(_tag=>'h3'))->as_text();
		$tube->{details} = ( $dd[$counter]->look_down(_tag=>'div', class => 'message')->look_down(_tag=>'p'))->as_text();

	}

	#print "DEBUG: $tube->{line}, $tube->{status}, $tube->{statusurl}, $tube->{details}\n ";
	push @tubes, $tube;
	$counter++;
}
$doc->delete();
#no longer generate CFF file
#&generateCff(\@tubes,$counter);
&generateRss(\@tubes,$counter);
&unlock;
&getrss;
}

sub generateUrl {
	my $url_start = 'http://www.tfl.gov.uk/tfl/livetravelnews/realtime/tube/tube-';
	my $line = shift;
	my $url_end = '-now.html';
	return $url_start.$line.$url_end;
}
sub generateCff {
	my ($arrayRef, $counter) = @_;
	my @tubes = @$arrayRef;
	my $j = $counter;
	my $i = 0;


	if($i<$j){		
		open(TUBECFF, ">$FILE_PSV");
		flock(TUBECFF, LOCK_EX);
		while ($i<$j){
			my $tube = $tubes[$i];
			my $line = $tube->{'line'};
			my $status =  $tube->{'status'};
			my $link =  $tube->{'statusurl'};
			my $details = $tube->{'details'};
			print TUBECFF "$line|$status|$details|$link\n";
			$i++;
		}
		flock(TUBECFF, LOCK_UN);
		close(TUBECFF);
	}
}

sub generateRss {
 my ($arrayRef, $counter) = @_;
 my @tubes = @$arrayRef;
 my $j = $counter;
 my $i = 0;

my $rss = new XML::RSS (version => '2.0');

$rss->channel(title          => 'London Tube Status',
              link           => $url,
	      language       => 'en',
	      description    => 'Latest tube line status - http://conor.net/code/tube/ v1.1(12/2008)',
	      copyright      => '(C) 2008 TfL',
	      pubDate        => $FORMATTED_TIME,
	      lastBuildDate  => $FORMATTED_TIME,
	      ttl	     => $TTL_MINUTES,
	      docs           => 'http://conor.net/code/tube/',
	      generator      => 'Conor Keegan',
	      managingEditor => 'info@conor.net',
	      webMaster      => 'info@conor.net'
);


$rss->image(title       => 'Transport for London',
            url         => 'http://www.tfl.gov.uk/tfl-global/images/roundel.gif',
	    link        => 'http://www.tfl.gov.uk/',
	    width       => 52,
	    height      => 44,
	    description => 'TfL Roundel'
	    );


if($i<$j){ 	
	while ($i<$j){
		my $tube = $tubes[$i];
		
		$rss->add_item(
		title => $tube->{'line'}.' - '.$tube->{'status'},
                description => $tube->{'details'},
		link  => $tube->{'statusurl'}
		);

		$i++;
	 }
}
	open(TUBERSS, ">$FILE_RSS");
	flock(TUBERSS, LOCK_EX);
	print TUBERSS 'content-type: text/xml\n';
	print TUBERSS $rss->as_string;
	flock(TUBERSS, LOCK_UN);
	close(TUBERSS);
}

