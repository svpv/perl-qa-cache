use ExtUtils::MakeMaker;
WriteMakefile
	NAME		=> 'qa::cache',
	VERSION		=> '0.04',
	AUTHOR		=> 'Alexey Tourbin <at@altlinux.org>',
	dist		=> { COMPRESS => 'gzip -9nf' },
	LIBS		=> '-lqacache',
	;
