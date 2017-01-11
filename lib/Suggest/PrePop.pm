package Suggest::PrePop;

use strict;
use warnings;
our $VERSION = '1.1.0';

use Moose;

use Cache::RedisDB;
use List::Util qw(uniq);

has cache_namespace => (
    is      => 'ro',
    isa     => 'Str',
    default => 'SUGGEST-PREPOP',
);

my $key_sep = '<>';

has 'scopes' => (
    is      => 'ro',
    isa     => 'ArrayRef',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $size = length($self->_cnt_key_base . $key_sep);
        no warnings('substr');
        return [sort { $a cmp $b }
              map { substr($_, $size) // '' }
              @{$self->_redis->keys($self->_cnt_key_base . '*')}];
    },
);

has _lex_key_base => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return join($key_sep, $self->cache_namespace, 'ITEMS_BY_LEX');
    },
);

has _cnt_key_base => (
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

sub _lex_key {
    my ($self, $scope) = @_;

    return ($scope)
      ? join($key_sep, $self->_lex_key_base, uc $scope)
      : $self->_lex_key_base;
}

sub _cnt_key {
    my ($self, $scope) = @_;

    return ($scope)
      ? join($key_sep, $self->_cnt_key_base, uc $scope)
      : $self->_cnt_key_base;
}

sub add {
    my ($self, $item, $count, @scopes) = @_;

    $count //= 1;    # Most of the time we'll just get a single entry
    @scopes = ('') unless @scopes;

    # For now, we just assume supplied items are well-formed
    my $redis = $self->_redis;

    my $how_many = 0;
    foreach my $scope (@scopes) {
        # Lexically sorted items are all zero-scored
        $redis->zadd($self->_lex_key($scope), 0, $item);

        # Score sorted items get incremented.
        $how_many += $redis->zincrby($self->_cnt_key($scope), $count, $item);
    }

    return $how_many;
}

sub ask {
    my ($self, $prefix, $count, @scopes) = @_;

    $count //= $self->top_count;  # If they don't say we try to find the 5 best.
    @scopes = ('') unless @scopes;

    my $redis = $self->_redis;

    my @full;

    foreach my $scope (@scopes) {
        push @full, grep { $_->[1] >= $self->min_activity }
          map { [$_, $redis->zscore($self->_cnt_key($scope), $_)] } @{
            $redis->zrangebylex(
                $self->_lex_key($scope),
                '[' . $prefix,
                '[' . $prefix . "\xff"
              ) // []};
    }

    @full = uniq map { $_->[0] } sort { $b->[1] <=> $a->[1] } @full;

    return [splice(@full, 0, $count)];
}

sub prune {
    my ($self, $keep, @scopes) = @_;

    $keep //= $self->entries_limit;
    @scopes = ('') unless @scopes;

    my $redis = $self->_redis;

    my $count = 0;

    foreach my $scope (@scopes) {
        # Count key is the one from which results are collated, so even
        # if things are out of sync, this is the one about which we care.
        next if ($redis->zcard($self->_cnt_key($scope)) <= $keep);

        my $final_index = -1 * $keep - 1;    # Range below is inclusive.
        my @to_prune =
          @{$redis->zrange($self->_cnt_key($scope), 0, $final_index)};
        $count += scalar @to_prune;

        # We're going to do this the slow way to keep them in sync.
        foreach my $item (@to_prune) {
            $redis->zrem($self->_cnt_key($scope), $item);
            $redis->zrem($self->_lex_key($scope), $item);
        }

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

=item scopes

Return an array reference with all currently known scopes.  Lazily computed on first call.

=item add($item, [$count], [@scopes])

Add C<$item> to the scope indices, or increment its current popularity. Any C<$count> is taken as the number of times it was seen; defaults to 1. 

=item ask($prefix, [$count], [@scopes])

Suggest the C<$count> most popular items n the given scopes matching the supplied C<$prefix>.  Defaults to 5.

=item prune([$count], [@scopes])

Prune all but the C<$count> most popular items from the given scopes.  Defaults to the instance C<entries_limit>.

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
