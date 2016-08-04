# NAME

Suggest::PrePop - suggestions based on prefix and popularity

# SYNOPSIS

    use Suggest::PrePop;
    my $suggestor = Suggest::Prepop->new;
    $suggestor->add("item - complete", 10);
    $suggestor->ask("item"); ["item - complete"];

# DESCRIPTION

Suggest::PrePop is a suggestion engine which uses a string prefix and
the popularity of items to make suggestions. This is pattern is most often
used for suggestions of partially typed items (e.g. web search forms.)

# METHODS

- new

    Constructor.  The following attributes (with defaults) may be set:

    \- `cache_namespace` ('SUGGEST-PREPOP') - `Cache::RedisDB` namespace to use for our accounting

    \- `min_activity` (5) - The minimum number of times an item must have been seen to be suggested

    \- `entries_limit` (32768) - The count of most popular entries to maintain in a purge event

    \- `top_count` (5) - The default number of entries to return from 'ask'

- add($item, \[$count\])

    Add `$item` to the index, or increment its current popularity. Any `$count` is taken as the number of times it was seen; defaults to 1.

- ask($prefix, \[$count\])

    Suggest the `$count` most popular items matching the supplied `$prefix`.  Defaults to 5.

- prune(\[$count\])

    Prune all but the `$count` most popular items.  Defaults to the instance `entries_limit`.

# AUTHOR
Inspire

# COPYRIGHT
Copyright 2016- Inspire.com

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO
