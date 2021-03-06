#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include <libwing/getopt.h>
#include <libwing/libwing.h>

/*TODO: Support a list of tab stops instead of regular spacing*/
static unsigned tabstop = 8;	/*-t; 8 = SUSv3 default*/
static int expand_all=0;	/*-a*/

static unsigned next_tab(unsigned c)
{
	return c + tabstop - c%tabstop;
}
static int is_tab(unsigned c)
{
	return (c%tabstop) == 0;
}

/*Copies in to out, unexpanding tabs.
  If an input error occurs, returns -1 immediately.
  On successful completion, returns zero.
  Does not close streams.
*/
int unexpand_file(FILE *in, FILE *out)
{
	unsigned c=0;
	int seen_nonspace=0;
	unsigned spaces_seen=0;
	int ch;

	while((ch=getc(in)) != EOF)
	{
		if(ch == '\n')
		{
			while(spaces_seen > 0)
			{
				putc(' ', out);
				spaces_seen--;
			}
			putc(ch, out);
			c=0;
			seen_nonspace=0;
			assert(spaces_seen == 0);
		}
		else if(seen_nonspace && !expand_all)
		{
			putc(ch, out);
		}
		else if(ch == '\t')
		{
			putc(ch, out);
			c=next_tab(c);
			spaces_seen=0;
		}
		else if(ch == ' ')
		{
			spaces_seen++;
			c++;
			if(is_tab(c))
			{
				putc((spaces_seen > 1)?'\t':' ', out);
				spaces_seen=0;
			}
		}
		else
		{
			while(spaces_seen > 0)
			{
				putc(' ', out);
				spaces_seen--;
			}
			putc(ch, out);
			c++;
			seen_nonspace=1;
		}
	}

	return ferror(in) ? -1 : 0;
}

int do_unexpand(const char *file, void *venv)
{
	int ret=0;
	FILE *in=fopen(file, "r");
	if(in == NULL)
	{
		perror(file);
		*(int *)venv = EXIT_FAILURE;
		return -1;
	}
	if(unexpand_file(in, stdout) == -1)
	{
		perror(file);
		*(int *)venv = EXIT_FAILURE;
		ret=-1;
	}
	fclose(in);
	return ret;
}

int main(int argc, char **argv)
{
	int opt;
	int i;
	int ret=0;

	while((opt = getopt(argc, argv, "t:a")) != -1)
	{
		switch(opt)
		{
		case '?':
			/*TODO: Output a usage message*/
			exit(EXIT_FAILURE);
		/*not reached*/
		case 't':
		{
			char *endptr;
			tabstop = strtoul(optarg, &endptr, 10);
			if(tabstop == 0 || *endptr != '\0')
			{
				fprintf(stderr, "%s: Bad tabstop '%s'\n", argv[0], optarg);
				exit(EXIT_FAILURE);
			}
		}
		break;
		case 'a':
			expand_all=1;
		break;
		default:
			fprintf(stderr, "%s: Internal error: getopt returned unexpected value '%c'\n", argv[0], opt);
			exit(EXIT_FAILURE);
		/*not reached*/
		}
	}

	if(argc == optind)
	{
		if(unexpand_file(stdin, stdout) == -1)
		{
			perror("(stdin)");
			exit(EXIT_FAILURE);
		}
		return 0;
	}

	for(i=optind; i<argc; i++)
	{
		if(wing_glob_foreach(argv[i], do_unexpand, &ret) == 0)
			fprintf(stderr, "%s: %s: No such file\n", argv[0], argv[i]);
	}

	return ret;
}
