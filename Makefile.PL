use ExtUtils::MakeMaker;
WriteMakefile
	NAME		=> 'qa::cache',
	VERSION_FROM	=> 'lib/qa/cache.pm',
	AUTHOR		=> 'Alexey Tourbin <at@altlinux.org>',
	dist		=> { COMPRESS => 'gzip -9nf' },
	LIBS		=> '-lqacache',
	;
