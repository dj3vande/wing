#include <stdio.h>
#include <stdlib.h>

/*TODO: Parameterize*/
/*TODO: Support a list of tab stops instead of regular spacing*/
#define TABSTOP	8

static unsigned next_tab(unsigned c)
{
	return c + TABSTOP - c%TABSTOP;
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

/*TODO: Accept command-line args*/
int main(void)
{
	if(expand_file(stdin, stdout) == -1)
	{
		perror("(stdin)");
		exit(EXIT_FAILURE);
	}

	return 0;
}
