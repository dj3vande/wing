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
	module_sourcetypes[module, type] = 1;
	module_platforms[module, platform] = 1;
	for (i=6; i<=NF; i++) {
		old = sources[module, platform, type];
		sources[module, platform, type] = old " " $i;
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

function write_rules(toolchain) {
	for (module in modules) {
		local_linkinputs = "";
		n = split(sources[module, "all", "C"], local_srcs, " ");
		for (i=1; i<=n; i++) {
			# sub substitutes in-place
			objname = local_srcs[i];
			sub(/\.c$/, ".o", objname);
			print "build " toolchain "/" objname " : " toolchain "cc " local_srcs[i];
			local_linkinputs = local_linkinputs " " toolchain "/" objname;
		}
		n = split(sources[module, "all", "library"], local_srcs, " ");
		for (i=1; i<=n; i++) {
			local_linkinputs = local_linkinputs " " toolchain "/" local_srcs[i] ".a";
		}
			
		if (modtypes[module] == "program") {
			print "build " toolchain "/" module " : " toolchain "link" local_linkinputs;
		} else if (modtypes[module] == "library") {
			print "build " toolchain "/" module ".a : " toolchain "ar" local_linkinputs;
		} else {
			print "--ERROR-- Unknown module type '" modtypes[module] "'";
		}
	}
}

function human_readable_dump() {
	for (module in modules) {
		print "Module "module" ("modtypes[module]"):";
		for (srctype in srctypes) {
			if((module,srctype) in module_sourcetypes) {
				print "\t"srctype" sources:"
				for (platform in platforms) {
					if ((module, platform, srctype) in sources) {
						print "\t\t["platform"]\t" sources[module, platform, srctype];
					}
				}
			}
		}
	}

	print "";
	for (platform in platforms) {
		print "Modules for platform " platform ":";
		for (module in modules) {
			if ((module, platform) in module_platforms) {
				print "\t" module;
			}
		}
	}
}

END {
	if (fail) {
		exit 1;
	}

	write_rules("host");

	#mingw is not quite right in this version (needs exesuffix)
	write_rules("mingw");

	write_rules("host64");
	write_rules("ppc");

	##winegcc requires exesuffix as well as rule special-casing; its
	##"executables" are pairs of %.exe and %.exe.so, where the .exe is
	##a shell script that calls Wine to run the program in the .exe.so.
	##So the rule we generate needs to be:
	##build <module>.exe <module>.exe.so : winelink <inputs>
	## out_base=<module>  ## winelink rule uses this (not ${out}) for -o
	#write_rules("wine");
}
