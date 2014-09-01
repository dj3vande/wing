#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include <libwing/getopt.h>

/*TODO: Support a list of tab stops instead of regular spacing*/
static unsigned tabstop = 8;	/*8 = SUSv3 default*/

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
		else if(seen_nonspace)	/*TODO: -a expands all tabs*/
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

int main(int argc, char **argv)
{
	int opt;
	int i;

	while((opt = getopt(argc, argv, "t:")) != -1)
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
		FILE *in=fopen(argv[i], "r");
		if(in == NULL)
		{
			perror(argv[i]);
			exit(EXIT_FAILURE);
		}
		if(unexpand_file(in, stdout) == -1)
		{
			perror(argv[i]);
			fclose(in);
			exit(EXIT_FAILURE);
		}
		fclose(in);
	}

	return 0;
}
