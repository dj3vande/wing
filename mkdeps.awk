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
END \
{
	if(outfile && depfile)
	{
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
## Resolving imports may generate errors, that we need to handle
## sensibly.
END { resolve_imports(); close(errfile); if (fail) exit 1; }

################################################################
## Name tracking & normalization
################################################################
## Global variables:
##   srcnames[id] = input name, for direct sources
##   srctypes[id] = input type, so we know if we should use
##     srcnames for lookups
##   basenames[id] = basename
##   dirs[id] = directories
## Internal variable:
##   next_id
################################################################
function get_id()
{
	return next_id++;
}
function save_source(dir, name, type, LOCALS, id)
{
	id = get_id();
	srcnames[id] = name;
	dirs[id] = dir;
	basenames[id] = get_base_name(type, name);
	srctypes[id] = type;
	return id;
}
function save_name(dir, name, LOCALS, id)
{
	id = get_id();
	dirs[id] = dir;
	basenames[id] = name;
	return id;
}
function get_srcname_by_id(id)
{
	return dirs[id] "/" srcnames[id];
}
function get_inputname_by_id(id, type, toolchain)
{
	if ((id in srcnames) && (srctypes[id] == type))
		return get_srcname_by_id(id);
	else
		return get_outname_by_id(id, type, toolchain);
}
function get_basename_by_id(id, toolchain)
{
	if(toolchain) toolchain = toolchain"/"
	return dirs[id] "/" toolchain basenames[id];
}
function get_outname_by_id(id, type, toolchain, LOCALS, base, ret)
{
	base = get_basename_by_id(id, toolchain);
	ret = get_template(toolchain, type);
	gsub("%", base, ret);
	return ret;
}

################################################################
## Assorted slicing and dicing
################################################################
function joininputs(start, sep)
{
	ret = $start;
	for(i=start+1; i<=NF; i++) ret = ret sep $i;
	return ret;
}
function unsplit(a, n, fs, LOCALS, ret)
{
	if(!fs) fs=" ";
	if(n==0) return "";
	ret=a[1];
	for(i=2; i<=n; i++)
		ret = ret fs a[i];
	return ret;
}

# On output, each arr1[left] is a fs-separated list of values of right
# such that arr2[left, right] exists.
# 1-dimensional indices of arr2 are ignored; 3+-dimensional indices are
# split at the first SUBSEP, so arr2[a, b, c] causes b SUBSEP c to go
# in arr1[a]'s list.
function collect(arr2, arr1, fs, LOCALS, both, left, right, n)
{
	if(!fs) fs=" ";
	for(n in arr1) delete arr1[n];
	for(both in arr2)
	{
		n = index(both, SUBSEP);
		if(n==0)
			continue;
		left = substr(both, 1, n-1);
		right = substr(both, n+length(SUBSEP));
		if(left in arr1)
			arr1[left] = arr1[left] fs;
		arr1[left] = arr1[left] right;
	}
}

# For each index (first,...) in arr2, the value indexed is placed in
# arr1[...].
# This gives us a way to fake nested arrays, i.e. it lets us use the
# array that arr2[first][...] would be if arrays were allowed to
# contain non-scalar values.
function getfirst(arr2, arr1, first, LOCALS, both, left, right, n)
{
	for(both in arr1) delete arr1[both];
	for(both in arr2)
	{
		n = index(both, SUBSEP);
		if(n==0) continue;
		left = substr(both, 1, n-1);
		right = substr(both, n+length(SUBSEP));
		if(left==first)
			arr1[right] = arr2[both];
	}
}

# Copy the contents of from to into, without destroying existing values.
# If an index appears in both arrays, the values are appended in into
# delimited by fs (default " ").
function combine(into, from, fs, LOCALS, idx)
{
	if(!fs) fs=" ";
	for(idx in from)
	{
		into[idx] = ((idx in into) ? (into[idx] fs) : "") from[idx];
	}
}


################################################################
## Tag file tracking
################################################################
## We need to do this before we get to anything with a 'next' rule.
################################################################
## Global variables:
##   tagdirs[dir,look] = 1 (directories to look in for tags file in dir)
##   export_paths[name, type, platform] = dirname of exported source
################################################################
$1 in link_rules \
{
	tagdirs[dir, dir] = 1;
}
$1 == "export" \
{
	export_paths[$5, $2, $3] = dir;
}
$1 == "import" \
{
	for (i=4; i<=NF; i++)
	{
		imp_platform = ($i, $3, $2) in export_paths ? $2 : "all";
		tagdirs[dir, export_paths[$i, $3, imp_platform]] = 1;
	}
}

END \
{
	collect(tagdirs, tags);
	for (dir in tags)
	{
		build_line("build " dir "/tags : ctags");
		build_line(" in_dirs = " tags[dir]);
		phonydeps["tags", dir"/tags"] = 1;
	}
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
$1 == "subdirectory" \
{
	ARGV[ARGC++] = "dir=" dir "/" $2;
	ARGV[ARGC++] = "module=" module;
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
$1 == "suffix" \
{
	type = $2;
	if(type in suffixes) warn("Replacing previously defined suffixes for filetype '" type "'");
	suffixes[type] = $3;
	temp = joininputs(3, "|");
	gsub("\\.", "\\.", temp);
	suffixres[type]="("temp")$";
	next;
}
$1 == "template" \
{
	toolchain = $2;
	type = $3;
	if((toolchain,type) in templates)
	{
		warn("Replacing previously defined template for toolchain '" toolchain "', filetype '" type "'");
	}
	templates[toolchain,type] = joininputs(4, " ");
	next;
}
function get_base_name(type, name)
{
	if(type in suffixres) gsub(suffixres[type], "", name);
	return name;
}
function get_template(toolchain, type)
{
	if((toolchain, type) in templates) return templates[toolchain, type];
	else if((toolchain, "all") in templates) return templates[toolchain, "all"];
	else if(type in suffixes) return "%" suffixes[type];
	else return "%";
}

################################################################
## Compile rules
################################################################
## File syntax:
##   compile <rulebase> <output-type> <input-type>
##   link <rulebase> <output-type> <input-type>...
################################################################
## Global variables:
##   compile_result[type] = type of output
##   compile_rules[type] = base rule to compile source type with
##   link_inputs[type] = input types for linking output type
##   link_rules[type] = base rule to link output type with
################################################################
$1 == "compile" \
{
	compile_result[$4] = $3;
	compile_rules[$4] = $2;
	next;
}
$1 == "link" \
{
	link_rules[$3] = $2;
	link_inputs[$3] = joininputs(4, " ");
	next;
}

################################################################
## Source file bookkeeping
################################################################
## Global variables:
##   sources[platform, type, module] = space-separated IDs
################################################################
function add_source_by_id(module, platform, type, id)
{
	sources[platform, type, module] = sources[platform, type, module] " " id;
	if(type in compile_result)
		add_source_by_id(module, platform, compile_result[type], id);
	else if(!index(link_inputs[modules[module]], type))
		warn("Don't know what to do with " type " source " get_basename_by_id(id) "!");
}
function add_source(module, platform, type, name, LOCALS, basename, id)
{
	add_source_by_id(module, platform, type, save_source(dir, name, type));
}

function get_inputs(module, platform, type, LOCALS, ret)
{
	ret = sources["all", type, module];
	ret = (ret ? ret " " : "") sources[platform, type, module];
	return ret;
}

################################################################
## Build rule generation
################################################################
## Argument variables:
##   outfile = file to write output to (default: stdout)
################################################################
## Global variables:
##   See compile rule input handling
################################################################
function build_line(str)
{
	if(outfile) print str > outfile;
	else print str;
}

function write_compile_rules(toolchain, LOCALS, platform, type, m, n, srclist, srcarray, tmparray, splitsources, srcname, outname)
{
	platform = toolchains[toolchain];
	getfirst(sources, srcarray, "all");
	getfirst(sources, tmparray, platform);
	combine(srcarray, tmparray);
	## srcarray[type, module] = list of sources

	for(type in compile_rules)
	{
		getfirst(srcarray, tmparray, type);
		srclist = "";
		for(m in tmparray) srclist = srclist " " tmparray[m];
		n = split(srclist, splitsources);
		for(i=1; i<=n; i++)
		{
			srcname = get_inputname_by_id(splitsources[i], type, toolchain);
			outname = get_outname_by_id(splitsources[i], compile_result[type], toolchain);
			build_line("build " outname " : " toolchain compile_rules[type] " " srcname);
		}
	}
}

#Global arrays:
#  toolchains[toolchain_name] = platform for toolchain
#  modules[id] = type (also serves as list of all known modules)
#  mod_platforms[id, platform] = 1 (list of module/platforms)
#  exports[name, type, platform] = ID of exported source
#  phonydeps[rule, dependency] = 1 (phony rule accumulator)


#Toolchains
# $2 = toolchain name
# $3 = platform
# $4 = subplatform
# $5 = bitness
$1 == "toolchain" { toolchains[$2] = $3; }


## Exports and imports
## Input files are read in breadth-first order, isn't necessarily a
## lexically sensible order; so resolving immediately can produce bad
## imports that "obviously should" get resolved cleanly.
## So we wait until we've done everything to do the resolution.
## An export for platform "all" will match any platform on an import; an
## export with a specific platform will only match that platform (only an
## export for "all" will match an import for "all").

$1 == "export" \
{
	type = $2;
	platform = $3;
	id = save_name(dir, $4);
	name = $5;
	if ((name, type, platform) in exports)
	{
		error("Export '" name "' (type '" type "', platform '" platform "') already exists with basename " get_basename_by_id(exports[name, type, platform]));
	}
	exports[name, type, platform] = id;
	next;
}

$1 == "import" \
{
	platform = $2;
	type = $3;
	mod_platforms[module, platform] = 1;
	for (i=4; i<=NF; i++)
	{
		id = get_id();
		imports[id] = $i;
		imports_type[id] = type;
		imports_module[id] = module;
		imports_platform[id] = platform;
		imports_location[id] = FILENAME ":" FNR;
	}
	next;
}

## This "really should" be an END rule, but because of interaction with
## the error-out handling (we want to detect all possible input errors
## before we start writing output), instead of matching END here it gets
## called from the error handling END rule before the "have we failed?"
## check.
function resolve_imports(LOCALS, impid, name, type, module, platform, imp_platform)
{
	for(impid in imports)
	{
		name = imports[impid];
		type = imports_type[impid];
		module = imports_module[impid];
		platform = imports_platform[impid];

		imp_platform = ((name, type, platform) in exports) ? platform : "all";
		if((name, type, imp_platform) in exports)
		{
			id = exports[name, type, imp_platform];
			add_source_by_id(module, platform, type, id);
		}
		else
		{
			## At resolve-imports time, FILENAME and FNR no
			## no longer contain the location of the bad import,
			## so we can't use error()
			errmsg(imports_location[impid] ": Error: Unresolved import '" name "' (type " type "', platform '" platform "')");
			fail=1;
		}
	}
}

#Collect module types and sanity-check
$1 in link_rules \
{
	module = save_name(dir, $2);
	#TODO: Check for duplicate names
	modules[module] = $1;
	next;
}
$1 == "rename" \
{
	newid = save_name(dir, $3);
	#TODO: Check for renaming on top of something that already exists
	renames[module, $2] = newid;
	next;
}

#Collect sources
$1 == "source" \
{
	platform = $2;
	type = $3;
	mod_platforms[module, platform] = 1;
	for (i=4; i<=NF; i++)
		add_source(module, platform, type, $i);
	next;
}

function get_linkinputs(module, toolchain, type, LOCALS, ret, platform, i, n, split_inputs)
{
	platform = toolchains[toolchain];

	n = split(get_inputs(module, platform, type), split_inputs);
	if(n > 0)
	{
		for(i=1; i<=n; i++)
			split_inputs[i] = get_inputname_by_id(split_inputs[i], type, toolchain);
		ret = unsplit(split_inputs, n);
	}

	return ret;
}

function write_rules(toolchain, LOCALS, module, split_types, linkinputs, inputsbytype, modname, realmod, outname, outbase, n, i, t)
{
	platform = toolchains[toolchain];

	write_compile_rules(toolchain);

	for (module in modules)
	{
		if (!((module, "all") in mod_platforms || (module, platform) in mod_platforms))
			continue;

		for(type in inputsbytype)
			delete inputsbytype[type];
		linkinputs = "";

		n = split(link_inputs[modules[module]], split_types);
		for(i=1; i<=n; i++)
		{
			t = get_linkinputs(module, toolchain, split_types[i]);
			if(t)
			{
				linkinputs = linkinputs " " t;
				inputsbytype[split_types[i]] = t;
			}
		}

		if((module, platform) in renames) realmod = renames[module, platform];
		else realmod = module;

		outname = get_outname_by_id(realmod, modules[module], toolchain);
		outbase = get_basename_by_id(realmod, toolchain);
		modname = get_basename_by_id(module);

		rule = toolchain link_rules[modules[module]];
		build_line("build " outname " : " rule linkinputs);
		build_line(" out_base = " outbase);
		for (type in inputsbytype)
		{
			build_line(" in_" type " = " inputsbytype[type]);
		}

		phonydeps[toolchain, outname] = 1;
		phonydeps[modname, outname] = 1;
		phonydeps["all", modname] = 1;
	}
}

END \
{
	for (tc in toolchains)
	{
		write_rules(tc);
	}

	collect(phonydeps, phony);
	for (rule in phony)
	{
		build_line("build " rule " : phony " phony[rule]);
	}

	if (outfile)
	{
		close(outfile);
	}
}
