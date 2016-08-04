use strict;
use warnings;

use Test::FailWarnings;
use Test::Most;
use Test::RedisDB;

use Suggest::PrePop;

my $server = Test::RedisDB->new;
plan(skip_all => 'Could not start test redis-server') unless $server;

my $former_val = $ENV{'REDIS_CACHE_SERVER'};
$ENV{'REDIS_CACHE_SERVER'} = $server->host . ':' . $server->port;

subtest 'defaults' => sub {
    my $suggestor = new_ok('Suggest::PrePop');

    cmp_ok $suggestor->cache_namespace, 'eq', 'SUGGEST-PREPOP',
      'Cache namespace';
    cmp_ok $suggestor->min_activity, '==', 5, 'Minimum activity';
    cmp_ok $suggestor->top_count,    '==', 5, 'Default item count to return';
    cmp_ok $suggestor->entries_limit, '==', 32768, 'Entries limit';

};

subtest 'simple' => sub {
    my $suggestor = new_ok('Suggest::PrePop');
    ok $suggestor->add("my fun search", 10), 'Can add an item';
    eq_or_diff $suggestor->ask("my", 10), ['my fun search'],
      'A single entry in the suggestions now';
    cmp_ok $suggestor->prune, '==', 0, 'Not enough entries to prune anything.';
    cmp_ok $suggestor->prune(0), '==', 1,
      'Removing all entries removes the one we added';
};

subtest 'full' => sub {
    my @test_data = (
        ['mycroft holmes',           10],
        ['mycroft',                  11],
        ['myc',                      2],
        ['sherlock holmes',          6],
        ['sherlock',                 5],
        ['surelock',                 1],
        ['doctor watson',            10],
        ['dr. waston',               6],
        ['dr watson',                6],
        ['watson',                   4],
        ['moriarty',                 15],
        ['prof moriarty',            8],
        ['prof. moriarty',           9],
        ['professor moriarty',       8],
        ['professor james moriarty', 6],
    );
    # Limit is only applied on prune.
    my $suggestor = new_ok('Suggest::PrePop' => [entries_limit => 10]);

    foreach my $item (@test_data) {
        ok $suggestor->add(@$item),
          'Add "' . $item->[0] . '" ' . $item->[1] . ' times';
    }

    eq_or_diff(
        $suggestor->ask('m'),
        ['moriarty', 'mycroft', 'mycroft holmes'],
        'Single letter prefix matches'
    );
    eq_or_diff(
        $suggestor->ask('my'),
        ['mycroft', 'mycroft holmes'],
        'Double letter prefix matches'
    );
    eq_or_diff(
        $suggestor->ask('dr'),
        ['dr watson', 'dr. waston'],
        'Lex order on same score matches'
    );
    eq_or_diff(
        $suggestor->ask('prof'),
        [
            'prof. moriarty',
            'prof moriarty',
            'professor moriarty',
            'professor james moriarty'
        ],
        'Score order more important'
    );
    eq_or_diff($suggestor->ask('prof', 1),
        ['prof. moriarty'], 'Can limit to just the top entry');

    eq_or_diff(
        $suggestor->ask('sher'),
        ['sherlock holmes', 'sherlock'],
        'Can find both sherlock entries'
    );

    cmp_ok $suggestor->prune, '==', 5, 'Prune back to the entries limit';

    eq_or_diff($suggestor->ask('sher'),
        ['sherlock holmes'], 'Leaving only one sherlock entry');

    cmp_ok $suggestor->prune(0), '==', 10, 'Can completely empty';

};

# Try to leave the environment unmangled, if possible.
$ENV{'REDIS_CACHE_SERVER'} = $former_val;

done_testing;
