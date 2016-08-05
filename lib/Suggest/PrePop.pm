package Suggest::PrePop;

use strict;
use warnings;
our $VERSION = '1.0.1';

use Moose;

use Cache::RedisDB;

has cache_namespace => (
    is      => 'ro',
    isa     => 'Str',
    default => 'SUGGEST-PREPOP',
);

my $key_sep = '<>';

has _lex_key => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return join($key_sep, $self->cache_namespace, 'ITEMS_BY_LEX');
    },
);

has _cnt_key => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return join($key_sep, $self->cache_namespace, 'ITEMS_BY_COUNT');
    },
);

has min_activity => (
    is      => 'ro',
    isa     => 'Int',
    default => 5,
);

has entries_limit => (
    is      => 'ro',
    isa     => 'Int',
    default => 32768,
);

has top_count => (
    is      => 'ro',
    isa     => 'Int',
    default => 5,
);

# Convenience
sub _redis { Cache::RedisDB->redis }

sub add {
    my ($self, $item, $count) = @_;

    $count //= 1;    # Most of the time we'll just get a single entry

    # For now, we just assume supplied items are well-formed
    my $redis = $self->_redis;

    # Lexically sorted items are all zero-scored
    $redis->zadd($self->_lex_key, 0, $item);

    # Score sorted items get incremented.
    return $redis->zincrby($self->_cnt_key, $count, $item);
}

sub ask {
    my ($self, $prefix, $count) = @_;

    $count //= $self->top_count;  # If they don't say we try to find the 5 best.

    my $redis = $self->_redis;

    my @full =
      map  { $_->[0] }
      sort { $b->[1] <=> $a->[1] }
      grep { $_->[1] >= $self->min_activity }
      map  { [$_, $redis->zscore($self->_cnt_key, $_)] } @{
        $redis->zrangebylex(
            $self->_lex_key,
            '[' . $prefix,
            '[' . $prefix . "\xff"
          ) // []};

    return [scalar(@full <= $count) ? @full : @full[0 .. $count - 1]];
}

sub prune {
    my ($self, $keep) = @_;

    $keep //= $self->entries_limit;

    my $redis = $self->_redis;

    # Count key is the one from which results are collated, so even
    # if things are out of sync, this is the one about which we care.
    return 0 if ($redis->zcard($self->_cnt_key) <= $keep);

    my $final_index = -1 * $keep - 1;    # Range below is inclusive.
    my @to_prune = @{$redis->zrange($self->_cnt_key, 0, $final_index)};
    my $count    = scalar @to_prune;

    # We're going to do this the slow way to keep them in sync.
    foreach my $item (@to_prune) {
        $redis->zrem($self->_cnt_key, $item);
        $redis->zrem($self->_lex_key, $item);
    }

    return $count;
}

1;

__END__

=encoding utf-8

=head1 NAME

Suggest::PrePop - suggestions based on prefix and popularity

=head1 SYNOPSIS

  use Suggest::PrePop;
  my $suggestor = Suggest::Prepop->new;
  $suggestor->add("item - complete", 10);
  $suggestor->ask("item"); ["item - complete"];

=head1 DESCRIPTION

Suggest::PrePop is a suggestion engine which uses a string prefix and
the popularity of items to make suggestions. This is pattern is most often
used for suggestions of partially typed items (e.g. web search forms.)

=head1 METHODS

=over 4

=item new

Constructor.  The following attributes (with defaults) may be set:

- C<cache_namespace> ('SUGGEST-PREPOP') - C<Cache::RedisDB> namespace to use for our accounting

- C<min_activity> (5) - The minimum number of times an item must have been seen to be suggested

- C<entries_limit> (32768) - The count of most popular entries to maintain in a purge event

- C<top_count> (5) - The default number of entries to return from 'ask'

=item add($item, [$count])

Add C<$item> to the index, or increment its current popularity. Any C<$count> is taken as the number of times it was seen; defaults to 1.

=item ask($prefix, [$count])

Suggest the C<$count> most popular items matching the supplied C<$prefix>.  Defaults to 5.

=item prune([$count])

Prune all but the C<$count> most popular items.  Defaults to the instance C<entries_limit>.

=back

=head1 AUTHOR
Inspire

=head1 COPYRIGHT
Copyright 2016- Inspire.com

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
