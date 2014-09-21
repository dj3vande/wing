#!/usr/bin/awk -f

#Collect a list of files
BEGIN { input_files = ""; }
FNR == 1 { input_files = input_files " " FILENAME; }

#Munch comments
$1 ~ /^#/ { next; }

#Global arrays:
#  toolchains[toolchain_name] = platform for toolchain
#  modules[module_name] = type (also serves as list of all known modules)
#  sources[module, platform, type] = list of sources for module grouped
#                                    by platform and type
#  mod_platforms[module_name, platform] = 1 (list of module/platforms)
#  templates[toolchain, type] = templates for output filenames
#  suffixes[type] = almost-ERE matching extension for input filenames
#                   (the ERE is formed by gsub("\\.","\\.",suffix) and then
#                   using "("suffix")$".)
#  rules[mod_type] = Base name of build rule ("link" or "ar" are currently
#                    known) to build modules of that type
#  exports[name, type, platform] = basename (including path) of exported source
#  export_paths[name, type, platform] = dirname of exported source
#  tagdirs[dir] = directories to look in for tags file in dir
#  phonydeps[rule, dependency] = 1 (phony rule accumulator)

# TODO: Make configurable
BEGIN {
	rules["program"] = "link";
	rules["library"] = "ar";
}

BEGIN { dir = "."; }

$1 == "subdirectory" {
	ARGV[ARGC++] = "dir=" dir "/" $2;
	ARGV[ARGC++] = dir "/" $2 "/" $3;
}

$1 == "suffix" {
	if($2 in suffixes) {
		print FILENAME ":" FNR ": Warning: Replacing previously defined suffixes for filetype '" $2 "'" >> "/dev/stderr";
	}
	suffixes[$2] = $3;
	for(i=4; i<=NF; i++) {
		suffixes[$2] = suffixes[$2] "|" $i;
	}
}

$1 == "template" {
	if(($2,$3) in templates) {
		print FILENAME ":" FNR ": Warning: Replacing previously defined template for toolchain '" $2 "', filetype '" $3 "'" >> "/dev/stderr";
	}
	templates[$2,$3] = $4;
	for(i=5; i<=NF; i++) {
		templates[$2,$3] = templates[$2,$3] " " $i;
	}
}

function get_base_name(type, name) {
	if(type in suffixes) {
		suffix = suffixes[type];
		gsub("\\.", "\\.", suffix);
		gsub("("suffix")$", "", name);
	}
	return name;
}

function get_out_name(toolchain, type, base) {
	if((toolchain, type) in templates) {
		retval = templates[toolchain, type];
		gsub("%", base, retval);
		return retval;
	}
	if(("all", type) in templates) {
		retval = templates["all", type];
		gsub("%", base, retval);
		return retval;
	}
	if(type in suffixes) {
		#If there are multiple suffixes allowed, assume the first
		#  one is preferred
		suffix = suffixes[type];
		sub("\\|.*", "", suffix);
		return base suffix;
	}
	return base;
}

#Toolchains
# $2 = toolchain name
# $3 = platform
# $4 = subplatform
# $5 = bitness
$1 == "toolchain" {
	toolchains[$2] = $3;
}


#Exports and imports
#Note that imports are resolved when we encounter them; it's up to the
#user to generate a non-cyclic dependency graph on subdirectory includes
#and put the includes in a toposorted order.
#This may change if a sufficiently compelling use case is produced.
#An export for platform "all" will match any platform on an import; an
#export with a specific platform will only match that platform (only an
#export for "all" will match an import for "all").

$1 == "export" {
	type = $2;
	platform = $3;
	basename = dir "/" $4;
	name = $5;
	if ((name, type, platform) in exports) {
		print FILENAME ":" FNR ": Export '" name "' (type '" type "', platform '" platform "') already exists with basename " exports[name, type, platform] >> "/dev/stderr";
		fail = 1;
	}
	exports[name, type, platform] = basename;
	export_paths[name, type, platform] = dir;
}

#Collect module types and sanity-check
($1 == "program") || ($1 == "library") {
	if (!(dir in tagdirs)) {
		tagdirs[dir] = dir;
	}
	if (!((dir "/" $2) in modules)) {
		modules[dir "/" $2] = $1;
	}
	if (modules[dir "/" $2] != $1) {
		print FILENAME ":" FNR ": Module " $2 " in directory " dir " was previously named with type " modules[dir "/" $2] >> "/dev/stderr";
		fail = 1;
	}
}

$3 == "import" {
	module = dir "/" $2;
	platform = $4;
	type = $5;
	if(!($1 in rules)) {
		print FILENAME ":" FNR ": Module " $2 " has unknown type '"$1"'" >> "/dev/stderr";
		fail=1;
	}
	mod_platforms[module, platform] = 1;
	for (i=6; i<=NF; i++) {
		if (($i, type, platform) in exports) {
			basename = exports[$i, type, platform];
			old = sources[module, platform, type];
			sources[module, platform, type] = old " " basename;
			tagdirs[dir] = tagdirs[dir] " " export_paths[$i, type, platform];
		} else if (($i, type, "all") in exports) {
			basename = exports[$i, type, "all"];
			old = sources[module, platform, type];
			sources[module, platform, type] = old " " basename;
			tagdirs[dir] = tagdirs[dir] " " export_paths[$i, type, "all"];
		} else {
			print FILENAME ":" FNR ": Import '" $i "' has not been exported from anywhere! (type '" type "', platform '" platform "'" >> "/dev/stderr";
			fail=1;
		}
	}
}

#Collect sources
($3 == "source") {
	module = dir "/" $2;
	platform = $4;
	type = $5;
	if(!($1 in rules)) {
		print FILENAME ":" FNR ": Module " $2 " has unknown type '"$1"'" >> "/dev/stderr";
		fail=1;
	}
	mod_platforms[module, platform] = 1;
	for (i=6; i<=NF; i++) {
		old = sources[module, platform, type];
		sources[module, platform, type] = old " " dir "/" $i;
	}
}

function get_sources(module, platform, type) {
	return sources[module, "all", type] " " sources[module, platform, type];
}

function build_line(str) {
	if (outfile) {
		print str > outfile;
	} else {
		print str;
	}
}

function write_rules(toolchain) {
	platform = toolchains[toolchain];

	for (module in modules) {
		if (!((module, "all") in mod_platforms || (module, platform) in mod_platforms)) {
			continue;
		}

		#Clear out inputs-by-type array, without breaking if it
		# doesn't yet exist as an array
		local_inputsbytype[""]="";
		for(type in local_inputsbytype) {
			delete local_inputsbytype[type];
		}

		local_linkinputs = "";
		n = split(get_sources(module, platform, "C"), local_srcs, " ");
		for (i=1; i<=n; i++) {
			# sub substitutes in-place
			basename = get_base_name("C", local_srcs[i]);
			objname = get_out_name(toolchain, "obj", basename);
			sub("[^/]*$", toolchain "/&", objname);
			build_line("build " objname " : " toolchain "cc " local_srcs[i]);
			local_inputsbytype["obj"] = local_inputsbytype["obj"] " " objname;
			local_linkinputs = local_linkinputs " " objname;
		}
		n = split(get_sources(module, platform, "library"), local_srcs, " ");
		for (i=1; i<=n; i++) {
			libname = get_out_name(toolchain, "library", local_srcs[i]);
			sub("[^/]*$", toolchain "/&", libname);
			local_linkinputs = local_linkinputs " " libname;
			local_inputsbytype["library"] = local_inputsbytype["library"] " " libname;
		}

		basename = module;
		sub("[^/]*$", toolchain "/&", basename);
		outname = get_out_name(toolchain, modules[module], basename);
		rule = toolchain rules[modules[module]];
		build_line("build " outname " : " rule local_linkinputs);
		build_line(" out_base = " basename);
		for (type in local_inputsbytype) {
			build_line(" in_" type " =" local_inputsbytype[type]);
		}

		if (modules[module] == "program") {
			phonydeps[toolchain, outname] = 1;
			phonydeps[module, outname] = 1;
			phonydeps["all", module] = 1;
		}
	}
}

END {
	if (fail) {
		exit 1;
	}

	for (tc in toolchains) {
		write_rules(tc);
	}

	for (dir in tagdirs) {
		build_line("build " dir "/tags : ctags");
		build_line(" in_dirs =" tagdirs[dir]);
		phonydeps["tags", dir"/tags"] = 1;
	}

	for (ruledep in phonydeps) {
		n=split(ruledep, temp, SUBSEP);
		if(n != 2) {
			print "Internal error: Bad array index '"ruledep"' (expected rule SUBSEP dependency)" >> "/dev/stderr";
			exit 1;
		}
		rule = temp[1];
		dep = temp[2];
		phony[rule] = phony[rule] " " dep;
	}
	for (rule in phony) {
		build_line("build " rule " : phony" phony[rule]);
	}

	if (outfile) {
		close(outfile);
		if(depfile) {
			print outfile ":" input_files > depfile;
			close(depfile);
		}
	}
}
