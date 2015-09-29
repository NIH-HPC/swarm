#!/usr/bin/perl
use lib "/usr/local/slurm/lib/site_perl/5.12.1/x86_64-linux-thread-multi";
use lib "/usr/local/slurm/lib/perl5/site_perl/5.18.2/x86_64-linux-thread-multi-ld";
use Slurm;
my $slurm = Slurm::new();
$jobs = $slurm->load_jobs();
JOB: foreach my $ref (@{$jobs->{job_array}}) {
  foreach my $key (sort keys %{$ref}) {
    print "$key:";
    if ($ref->{$key} =~ /ARRAY/) {
      if (@{$ref->{$key}}) {
        print " @{$ref->{$key}}";
      }
    }
    else {
      print " $ref->{$key}";
    }
    if ($key eq 'job_state') {
       print " (".$slurm->job_state_string($ref->{$key}).")";
    }
    print "\n";
  } 
}
