#include <stdio.h>
#include <stdlib.h>

#include <libwing/getopt.h>

/*TODO: Support a list of tab stops instead of regular spacing*/
static unsigned tabstop = 8;	/*8 = SUSv3 default*/

static unsigned next_tab(unsigned c)
{
	return c + tabstop - c%tabstop;
}

/*Copies in to out, expanding tabs.
  If an input error occurs, returns -1 immediately.
  On successful completion, returns zero.
  Does not close streams.
*/
int expand_file(FILE *in, FILE *out)
{
	unsigned c=0;
	int ch;

	while((ch=getc(in)) != EOF)
	{
		if(ch == '\t')
		{
			unsigned nt=next_tab(c);
			while(c < nt)
			{
				putc(' ', out);
				c++;
			}
		}
		else
		{
			putc(ch, out);
			switch(ch)
			{
			case '\b': if(c > 0) c--; break;
			case '\n': c=0;           break;
			default:   c++;           break;
			}
		}
	}

	return ferror(in) ? -1 : 0;
}

int main(int argc, char **argv)
{
	int opt;

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

	/*TODO: Take files to expand on the command line*/
	if(argc > optind)
	{
		fprintf(stderr, "%s: NYI: I don't accept files on the command line yet\n", argv[0]);
		exit(EXIT_FAILURE);
	}

	if(expand_file(stdin, stdout) == -1)
	{
		perror("(stdin)");
		exit(EXIT_FAILURE);
	}

	return 0;
}
