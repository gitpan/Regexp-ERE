use strict;
use warnings;

use Regexp::ERE qw(
    &ere_to_nfa
    &nfa_inter
    &nfa_union
    &nfa_isomorph
    &nfa_to_input_constraints
    &nfa_to_min_dfa
    &nfa_to_regex
);

sub expand_input_constraints {
    my ($in_cons) = @_;
    my $widget = $$in_cons[0];
    my $prefixes = ref($widget) ? $widget : ['.*'];
    my $suffixes
      = @$in_cons > 1
      ? expand_input_constraints([@$in_cons[1..$#$in_cons]])
      : ['']
    ;
    return [
        map {
            my $prefix = $_;
            map { $prefix . $_ } @$suffixes
        }
        @$prefixes
    ];
}

# simliar to shell expression before brace expansion
sub input_constraints_to_str {
    my ($input_constraints) = @_;
    return join('',
        map {
            !ref($_)
          ? '*'
          : '{' . join(',',
                 map {
                     my $word = $_;
                     $word =~ s/([{}\\\$,])/\\$1/xmsg;
                     $word;
                 }
                 @$_
            ) . '}'
        }
        @$input_constraints
    );
}

our @test_cases;
my $num_tests = 0;
BEGIN {
    @test_cases = (
        [
            [ # regexs to be and-ed
                '^(beg1|beg2)-'
              , '-(mid1|mid2)-'
              , '-(end1|end2)$'
              , '^[^-]*-[^-]*-[^-]*$'
            ]
          , [ # expected input constraints
                [ 'beg1', 'beg2' ],
              , [ '-mid1', '-mid2' ]
              , [ '-end1', '-end2' ]
            ]
        ]
      , [
            [
                '^[^@]+@[^@]+$'
              , '^(john(\\.smith)?|fred(\\.miller)?)@.*$'
              , '^.*@(company1\.com|company2\.com)$'
            ]
          , [
                ['fred.miller@', 'fred@', 'john.smith@', 'john@']
              , ['company1.com', 'company2.com']
            ]
        ]
      , [
            [
                '^ab'
              , 'bc$'
            ]
          , [
                ['ab']
              , 'free text'
              , ['c']
            ]
        ]
      , [
            [
                '^(x,?){10}$'
              , '^x+(,x+)*$'
            ]
          , [
                'free text'
              , ['x' ]
            ]
        ]
      , [
            [
                '^[^@]*@([^@]+\.)*domain[12]\.com$'
            ]
          , [
                'free text'
              , ['@']
              , 'free text'
              , ['domain1.com', 'domain2.com']
            ]
        ]
    );
    for my $test_case (@test_cases) {
        my $nfa = nfa_inter(map { ere_to_nfa($_) } @{$$test_case[0]});
        my ($input_fields, $split_perlre) = nfa_to_input_constraints($nfa);
        $$test_case[2] = $nfa;
        $$test_case[3] = $input_fields;
        $$test_case[4] = $split_perlre;
        $$test_case[5] = expand_input_constraints($input_fields);
        $num_tests
         += 1                   # input constraints comparison
          + @{$$test_case[5]}   # perl re match
          + 1                   # input constraints weaker than nfa
        ;
    }
}

use Test::More tests => $num_tests;

for my $test_case (@test_cases) {
    is_deeply(
        $$test_case[1]
      , $$test_case[3]
      , 'input constraints comparison: '
      . join(', ', @{$$test_case[0]})
      . ' exp: '
      . input_constraints_to_str($$test_case[1])
      . ' got: '
      . input_constraints_to_str($$test_case[3])
    );
    for my $string (@{$$test_case[5]}) {
        my $perlre = $$test_case[4];
        ok(
            $string =~ $perlre
          , "input constraints weaker perl re match $string against $perlre"
        );
    }
    my $dfa1 = nfa_to_min_dfa($$test_case[2]);
    my $dfa2 = nfa_to_min_dfa(nfa_inter(
        $dfa1
      , nfa_union(map { ere_to_nfa("^$_\$")  } @{$$test_case[5]})
    ));
    ok(
        nfa_isomorph($dfa1, $dfa2)
      , 'input constraints weaker than nfa ' . nfa_to_regex($$test_case[2])
    );
}
