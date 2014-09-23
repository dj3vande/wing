#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libwing/getopt.h>
#include <libwing/libwing.h>
#include <libwing/regex.h>

regex_t grep_regex;
unsigned long matched;

/*Reads lines from in, and writes ones that match grep_regex to out.
  If an error occurs (on file read or memory allocation), returns
  -1 immediately.  On successful completion, returns zero.
  Does not close streams.
*/
int grep_file(FILE *in, FILE *out)
{
	char *readbuf;
	size_t readsize=0;
	char *newline;
	int errno_save=0;

	if((readbuf=malloc(readsize=128)) == NULL)
		return -1;

	while(fgets(readbuf, readsize, in))
	{
		/*Make sure we have a whole line*/
		newline=strchr(readbuf, '\n');
		while(newline == NULL)
		{
			size_t old_readsize=readsize;
			char *t=realloc(readbuf, 2*readsize);
			if(t==NULL)
			{
				errno_save=errno;
				free(readbuf);
				errno=errno_save;
				return -1;
			}
			readsize*=2;
			readbuf=t;
			if(fgets(readbuf+old_readsize, old_readsize, in)==NULL)
			{
				/*No newline at EOF, or read error.
				  Process this line before we bail out.
				*/
				errno_save=errno;
				break;
			}
			newline=strchr(readbuf, '\n');
		}

		if(regexec(&grep_regex, readbuf, 0, NULL, 0) == 0)
		{
			matched++;
			fputs(readbuf, out);
		}
	}

	if(errno_save != 0)
		errno=errno_save;
	return feof(in) ? 0 : -1;
}

int do_grep(const char *file, void *venv)
{
	int *error_occurred = venv;
	FILE *in=fopen(file, "r");
	if(in==NULL)
	{
		perror(file);
		*error_occurred=1;
		return 0;
	}
	if(grep_file(in, stdout) == -1)
	{
		perror(file);
		*error_occurred=1;
	}
	fclose(in);
	return 0;
}

int main(int argc, char **argv)
{
	int opt;
	int i;
	int ret;
	int error_occurred=0;

	while((opt = getopt(argc, argv, "")) != -1)
	{
		switch(opt)
		{
		case '?':
			/*TODO: Output a usage message*/
			exit(EXIT_FAILURE);
		/*not reached*/
		break;
		default:
			fprintf(stderr, "%s: Internal error: getopt returned unexpected value '%c'\n", argv[0], opt);
			exit(EXIT_FAILURE);
		/*not reached*/
		}
	}

	if(argc == optind)
	{
		fprintf(stderr, "Usage: %s <pattern> [file ...]\n", argv[0]);
		exit(EXIT_FAILURE);
	}

	ret=regcomp(&grep_regex, argv[optind], REG_NOSUB);
	if(ret != 0)
	{
		char errbuf[256];
		regerror(ret, &grep_regex, errbuf, sizeof errbuf);
		fprintf(stderr, "%s: Regexp '%s': %s\n", argv[0], argv[optind], errbuf);
		exit(EXIT_FAILURE);
	}

	if(argc == optind+1)
	{
		if(grep_file(stdin, stdout) == -1)
		{
			perror("(stdin)");
			exit(EXIT_FAILURE);
		}
		return 0;
	}

	for(i=optind+1; i<argc; i++)
	{
		if(wing_glob_foreach(argv[i], do_grep, &error_occurred) == 0)
			fprintf(stderr, "%s: %s: No such file\n", argv[0], argv[i]);
	}

	regfree(&grep_regex);

	return error_occurred ? EXIT_FAILURE : (matched==0);
}
