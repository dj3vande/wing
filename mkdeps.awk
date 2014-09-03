#!awk -f

#Munch comments
$1 ~ /^#/ { next; }

#Collect names of things
{
	modules[$2] = 1;
	srctypes[$5] = 1;
	platforms[$4] = 1;
}

#Collect sources
($3 == "source") {
	module = $2;
	platform = $4;
	type = $5;
	for (i=6; i<=NF; i++) {
		key = module "," platform "," type;
		old = sources[key];
		sources[key] = old " " $i;
	}
}

#Collect module types and sanity-check
{
	if (!($2 in modtypes)) {
		modtypes[$2] = $1;
	}
	if (modtypes[$2] != $1) {
		print FILENAME ":" FNR ": Module " $2 " was previously named with type " modtypes[$2];
		fail = 1;
	}
}

END {
	if (fail) {
		exit 1;
	}
	for (module in modules) {
		print "Module "module" ("modtypes[module]"):";
		for (srctype in srctypes) {
			print "\t"srctype" sources:"
			for (platform in platforms) {
				key = module "," platform "," srctype;
				if (key in sources) {
					print "\t\t["platform"]\t" sources[key];
				}
			}
		}
	}
}
