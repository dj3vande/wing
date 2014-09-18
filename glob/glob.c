#include <assert.h>
#include <stdio.h>

#include <libwing/libwing.h>

int write_name(const char *n, void *env)
{
	assert(env==NULL);
	printf("  %s\n", n);
	return 0;
}

int main(int argc, char **argv)
{
	int i;
	int n;

	for(i=1; i<argc; i++)
	{
		printf("Globbing '%s'...\n", argv[i]);
		n=wing_glob_foreach(argv[i], write_name, NULL);
		if(n>=0)
			printf("...%d files matched\n", n);
	}

	return 0;
}
