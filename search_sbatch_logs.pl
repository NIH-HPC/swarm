#!/usr/local/bin/perl
use Storable;
use Date::Parse qw(str2time);
use FileHandle;
use Fcntl ':flock';
use strict;

my $store = '/usr/local/logs/swarm.store';

my $HR = retreive_old_data();
foreach my $user (sort keys %{$HR->{swarm}}) {
  foreach my $date (sort keys %{$HR->{swarm}->{$user}}) {
    foreach my $tag (sort keys %{$HR->{swarm}->{$user}->{$date}}) { 
      if ($tag eq $ARGV[0]) {
        print "$date $tag $user $HR->{swarm}->{$user}->{$date}->{$tag}->{jobid}\n";
        exit;
      }
    }
  }
}

#==================================================================================================
sub retreive_old_data
{
  open(FH, ">$store.lck")           or die "can't create lock $store.lck $!";
  flock(FH, 2)                        or die "can't flock $store.lck $!";
  my $hr = retrieve($store) if (-f $store);
  close(FH)                           or die "can't remove lock $store.lck $!";
  unlink "$store.lck";
  return $hr;
}
#==================================================================================================
