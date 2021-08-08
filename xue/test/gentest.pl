#!/usr/bin/env perl

use warnings;
use strict;

# generate benchplus.xue
print "[*] Generating 'test/scripts/benchplus.xue'\n";

open(EvilPlus, '>', 'test/scripts/benchplus.xue') or die $!;
print EvilPlus "echo 3${\(\" + 3\" x 10000)} - 3;";
close(EvilPlus);


# generate evil-plus.xue
print "[*] Generating 'test/scripts/evil-plus.xue'\n";

open(EvilPlus, '>', 'test/scripts/evil-plus.xue') or die $!;
print EvilPlus "echo 3${\(\" + 3\" x 10000000)} - 3;";
close(EvilPlus);


# generate evil-plus-plus.xue
print "[*] Generating 'test/scripts/evil-plus-plus.xue'\n";

open(EvilPlusPlus, '>', 'test/scripts/evil-plus-plus.xue') or die $!;
print EvilPlusPlus "echo 3${\(\" + 3\" x 100000000)} - 3;";
close(EvilPlusPlus);
