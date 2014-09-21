#!/usr/bin/awk -f

################################################################
## depfile handling
################################################################
## Argument variables:
##   outfile = file to write output to (default: stdout)
##   depfile = file to write dependencies to (default: none)
################################################################
## Global variables:
##   input_files = list of files read
################################################################
BEGIN { input_files = ""; }
FNR == 1 { input_files = input_files " " FILENAME; }
END {
	if(outfile && depfile) {
		print outfile ":" input_files > depfile;
		close(depfile);
	}
}

################################################################
## Munch comments (needs to come after any FNR==1 rules)
################################################################
$1 ~ /^#/ { next; }

################################################################
## Error handling
################################################################
## Argument variable:
##   errfile = file to write error messages to (default: stderr)
################################################################
BEGIN { if(!errfile) errfile="/dev/stderr"; }
function errmsg(msg) { print msg >> errfile; }
function warn(msg) { errmsg(FILENAME ":" FNR ": Warning: " msg); }
function error(msg) { errmsg(FILENAME ":" FNR ": Error: " msg); fail=1; }
function die(msg) { errmsg(msg); fail=1; exit 1; }
END {
	close(errfile);
	if (fail) exit 1;
}

################################################################
## Assorted slicing and dicing
################################################################
function joininputs(start, sep) {
	ret = $start;
	for(i=start+1; i<=NF; i++) ret = ret sep $i;
	return ret;
}

################################################################
## Subdirectory import handling
################################################################
## File syntax:
##   subdirectory <subdir-name> <filename>
################################################################
## Global variables:
##   dir = directory of current file, relative to top level
################################################################
BEGIN { dir = "."; }
$1 == "subdirectory" {
	ARGV[ARGC++] = "dir=" dir "/" $2;
	ARGV[ARGC++] = dir "/" $2 "/" $3;
	next;
}

################################################################
## Filename generation
################################################################
## File syntax:
##   suffix <type> <suffix>...
##   template <toolchain> <type> <template-%-is-basename>
################################################################
## Global variables:
##   suffixes[type] = suffix for outputs
##   suffixres[type] = end-anchored ERE matching suffix of inputs
##   templates[toolchain, type] = template for building outname
################################################################
$1 == "suffix" {
	type = $2;
	if(type in suffixes) warn("Replacing previously defined suffixes for filetype '" type "'");
	suffixes[type] = $3;
	temp = joininputs(3, "|");
	gsub("\\.", "\\.", temp);
	suffixres[type]="("temp")$";
	next;
}
$1 == "template" {
	toolchain = $2;
	type = $3;
	if((toolchain,type) in templates) {
		warn("Replacing previously defined template for toolchain '" toolchain "', filetype '" type "'");
	}
	templates[toolchain,type] = joininputs(4, " ");
	next;
}
function get_base_name(type, name) {
	if(type in suffixres) gsub(suffixres[type], "", name);
	return name;
}
function get_template(toolchain, type) {
	if((toolchain, type) in templates) return templates[toolchain, type];
	else if((toolchain, "all") in templates) return templates[toolchain, "all"];
	else if(type in suffixes) return "%" suffixes[type];
	else return "%";
}
function get_out_name(toolchain, type, base) {
	ret = get_template(toolchain, type);
	gsub("%", base, ret);
	return ret;
}

#Global arrays:
#  toolchains[toolchain_name] = platform for toolchain
#  modules[module_name] = type (also serves as list of all known modules)
#  sources[module, platform, type] = list of sources for module grouped
#                                    by platform and type
#  mod_platforms[module_name, platform] = 1 (list of module/platforms)
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
		error("Export '" name "' (type '" type "', platform '" platform "') already exists with basename " exports[name, type, platform]);
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
		error("Module " $2 " in directory " dir " was previously named with type " modules[dir "/" $2]);
	}
}

$3 == "import" {
	module = dir "/" $2;
	platform = $4;
	type = $5;
	if(!($1 in rules)) {
		error("Module " $2 " has unknown type '"$1"'");
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
			error("Import '" $i "' has not been exported from anywhere! (type '" type "', platform '" platform "'");
		}
	}
}

#Collect sources
($3 == "source") {
	module = dir "/" $2;
	platform = $4;
	type = $5;
	if(!($1 in rules)) {
		error("Module " $2 " has unknown type '"$1"'");
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
	for (tc in toolchains) {
		write_rules(tc);
	}

	for (dir in tagdirs) {
		build_line("build " dir "/tags : ctags");
		build_line(" in_dirs =" tagdirs[dir]);
		phonydeps["tags", dir"/tags"] = 1;
	}

	for (ruledep in phonydeps) {
		n=split(ruledep, temparr, SUBSEP);
		if(n != 2) {
			die("Internal error: Bad array index '"ruledep"' (expected rule SUBSEP dependency)");
		}
		rule = temparr[1];
		dep = temparr[2];
		phony[rule] = phony[rule] " " dep;
	}
	for (rule in phony) {
		build_line("build " rule " : phony" phony[rule]);
	}

	if (outfile) {
		close(outfile);
	}
}
