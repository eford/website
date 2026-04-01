#!/usr/bin/env julia
"""
parse_publications.jl

Reads a BibTeX file exported from NASA ADS, fetches abstracts via the ADS API,
and writes one TOML file per publication to _data/publications/YEAR/.

Usage (run from site root):
    julia --project=scripts/parse_publications scripts/parse_publications/parse_publications.jl references.bib
    julia --project=scripts/parse_publications scripts/parse_publications/parse_publications.jl references.bib --config.ads_config
    julia --project=scripts/parse_publications scripts/parse_publications/parse_publications.jl references.bib --skip-ads
    julia --project=scripts/parse_publications scripts/parse_publications/parse_publications.jl references.bib --dry-run
"""

using HTTP
using JSON3

# ---------------------------------------------------------------------------
# ADS journal macro expansion
# ---------------------------------------------------------------------------

const ADS_MACROS = Dict(
    "\\apj"      => "ApJ",
    "\\apjl"     => "ApJL",
    "\\apjs"     => "ApJS",
    "\\aj"       => "AJ",
    "\\aap"      => "A&A",
    "\\aapr"     => "A&A Rev.",
    "\\aaps"     => "A&AS",
    "\\mnras"    => "MNRAS",
    "\\pasp"     => "PASP",
    "\\pasa"     => "PASA",
    "\\pasj"     => "PASJ",
    "\\nat"      => "Nature",
    "\\natast"   => "Nature Astronomy",
    "\\sci"      => "Science",
    "\\icarus"   => "Icarus",
    "\\araa"     => "ARA&A",
    "\\ssr"      => "Space Sci. Rev.",
    "\\solphys"  => "Sol. Phys.",
    "\\physrep"  => "Phys. Rep.",
    "\\prd"      => "Phys. Rev. D",
    "\\prl"      => "Phys. Rev. Lett.",
    "\\pre"      => "Phys. Rev. E",
    "\\jgr"      => "J. Geophys. Res.",
    "\\aplett"   => "Astrophys. Lett.",
    "\\asr"      => "Adv. Space Res.",
    "\\memsai"   => "Mem. Soc. Astron. Italiana",
)

# ---------------------------------------------------------------------------
# LaTeX → Unicode conversion
# ---------------------------------------------------------------------------

const LATEX_UNICODE = Dict(
    "\\alpha"    => "α",  "\\beta"     => "β",  "\\gamma"    => "γ",
    "\\delta"    => "δ",  "\\epsilon"  => "ε",  "\\zeta"     => "ζ",
    "\\eta"      => "η",  "\\theta"    => "θ",  "\\iota"     => "ι",
    "\\kappa"    => "κ",  "\\lambda"   => "λ",  "\\mu"       => "μ",
    "\\nu"       => "ν",  "\\xi"       => "ξ",  "\\pi"       => "π",
    "\\rho"      => "ρ",  "\\sigma"    => "σ",  "\\tau"      => "τ",
    "\\upsilon"  => "υ",  "\\phi"      => "φ",  "\\chi"      => "χ",
    "\\psi"      => "ψ",  "\\omega"    => "ω",
    "\\Gamma"    => "Γ",  "\\Delta"    => "Δ",  "\\Theta"    => "Θ",
    "\\Lambda"   => "Λ",  "\\Xi"       => "Ξ",  "\\Pi"       => "Π",
    "\\Sigma"    => "Σ",  "\\Upsilon"  => "Υ",  "\\Phi"      => "Φ",
    "\\Psi"      => "Ψ",  "\\Omega"    => "Ω",
    "\\sim"      => "~",  "\\approx"   => "≈",  "\\leq"      => "≤",
    "\\geq"      => "≥",  "\\neq"      => "≠",  "\\pm"       => "±",
    "\\times"    => "×",  "\\cdot"     => "·",  "\\infty"    => "∞",
    "\\odot"     => "⊙",  "\\oplus"    => "⊕",  "\\circ"     => "°",
    "\\AA"       => "Å",  "\\deg"      => "°",
    "\\,"        => " ",  "\\ "        => " ",  "\\;"        => " ",
)

const SUPERSCRIPT_MAP = Dict(
    '0'=>'⁰','1'=>'¹','2'=>'²','3'=>'³','4'=>'⁴',
    '5'=>'⁵','6'=>'⁶','7'=>'⁷','8'=>'⁸','9'=>'⁹',
    '+'=>'⁺','-'=>'⁻','n'=>'ⁿ',
)

const SUBSCRIPT_MAP = Dict(
    '0'=>'₀','1'=>'₁','2'=>'₂','3'=>'₃','4'=>'₄',
    '5'=>'₅','6'=>'₆','7'=>'₇','8'=>'₈','9'=>'₉',
)

"""
    expand_macros(text) -> String

Replace ADS journal macros with their expanded forms.
Macros must not be immediately followed by a letter to avoid partial matches.
"""
function expand_macros(text::AbstractString)::String
    for (this_macro, expansion) in ADS_MACROS
        # Escape the macro for use in a regex, then ensure it's not
        # followed by another letter (e.g., avoid \\apjl matching \\apj)
        pattern = Regex(escape_string(this_macro) * "(?![a-zA-Z])")
        text = replace(text, pattern => expansion)
    end
    return text
end

"""
    latex_to_unicode(text) -> String

Convert simple LaTeX expressions to Unicode. Handles Greek letters, common
math symbols, single-character super/subscripts, and removes grouping braces.
Complex expressions that cannot be cleanly converted are left as-is.
"""
function latex_to_unicode(text::AbstractString)::String
    # Replace known symbols (longest keys first to avoid partial matches)
    for key in sort(collect(keys(LATEX_UNICODE)), by=length, rev=true)
        text = replace(text, key => LATEX_UNICODE[key])
    end

    # Superscripts: ^{x} or ^x for single supported char
    text = replace(text, r"\^\{([0-9+\-n])\}" =>
        m -> string(get(SUPERSCRIPT_MAP, m[3], m[3])))
    text = replace(text, r"\^([0-9+\-n])" =>
        m -> string(get(SUPERSCRIPT_MAP, m[2], m[2])))

    # Subscripts: _{x} or _x for single digit
    text = replace(text, r"_\{([0-9])\}" =>
        m -> string(get(SUBSCRIPT_MAP, m[3], m[3])))
    text = replace(text, r"_([0-9])" =>
        m -> string(get(SUBSCRIPT_MAP, m[2], m[2])))

    # Remove braces used purely for grouping: {M} -> M
    text = replace(text, r"\{([^{}]+)\}" => s"\1")

    # Strip $ delimiters only if no backslash remains inside
    # (i.e., complex LaTeX is left alone)
    #=
    text = replace(text, r"\$([^$]+)\$" => function(m)
        inner = m[2:end-1]
        occursin('\\', inner) ? m : inner
    end)
    =#
    return strip(text)
end

"""
    clean_value(text) -> String

Strip outer braces, expand macros, and convert LaTeX to Unicode.
"""
function clean_value(text::AbstractString)::String
    text = strip(text)
    # Strip a single layer of outer braces if present
    if startswith(text, "{") && endswith(text, "}")
        text = text[2:end-1]
    end
    text = expand_macros(text)
    text = latex_to_unicode(text)
    return strip(text)
end

# ---------------------------------------------------------------------------
# BibTeX parser
# ---------------------------------------------------------------------------

"""
    parse_bibtex(bib_text) -> Vector{Dict{String,String}}

Parse ADS-format BibTeX into a vector of entry dicts.
Each dict has string keys (lowercased field names) and string values,
plus "ENTRYTYPE" and "ID".

ADS BibTeX has a consistent format:
  @article{key,
    field = {value},...
  }
Values may be wrapped in braces or quotes, and may span multiple lines.
"""
#=
function parse_bibtex(bib_text::String)::Vector{Dict{String,String}}
    entries = Dict{String,String}[]
    i = 1
    n = length(bib_text)

    while i <= n
        # Scan forward to the next '@'
        at_pos = findnext('@', bib_text, i)
        isnothing(at_pos) && break

        # Extract the entry block starting at '@' using brace tracking
        block = extract_entry_block(bib_text, at_pos)
        if isnothing(block)
            i = nextind(bib_text, at_pos)
            continue
        end

        entry = parse_entry_block(block)
        isnothing(entry) || push!(entries, entry)

        # Advance past the end of this block
        i = at_pos + length(block)
        i = nextind(bib_text, i - 1)
    end

    return entries
end
=# 
# Orig
function parse_bibtex(bib_text::AbstractString)::Vector{Dict{String,String}}
    entries = Dict{String,String}[]

    # Split into individual entry blocks on @ that starts a new entry.
    # We find each @TYPE{ position and slice between them.
    entry_starts = findall(r"(?m)^@\w+\s*\{", bib_text)
    isempty(entry_starts) && return entries

    for i in eachindex(entry_starts)
        start_pos = first(entry_starts[i])
        @info i 
        # The entry runs until the matching closing brace
        block = extract_entry_block(bib_text, start_pos)
        isnothing(block) && continue
        entry = parse_entry_block(block)
        isnothing(entry) || push!(entries, entry)
    end

    return entries
end


"""
    extract_entry_block(text, start_pos) -> Union{String, Nothing}

Extract a complete BibTeX entry block starting at `start_pos` by tracking
brace depth. Returns the full string from @ to the matching closing brace.
"""
function extract_entry_block(text::String, start_pos::Int)::Union{String,Nothing}
    # First confirm this @ is actually a BibTeX entry type (not an email etc.)
    # by checking that @WORD{ follows
    m = match(r"^@\w+\s*\{", text[start_pos:min(end, start_pos+50)])
    isnothing(m) && return nothing

    depth = 0
    i = start_pos
    n = length(text)
    found_open = false

    while i <= n
        c = text[i]
        if c == '{'
            depth += 1
            found_open = true
        elseif c == '}'
            depth -= 1
            if found_open && depth == 0
                return text[start_pos:i]
            end
        elseif c == '\\'
            # Skip escaped character to avoid counting escaped braces
            i = nextind(text, i)
            i > n && break
        end
        i = nextind(text, i)
    end
    return nothing
end
#= Orig
function extract_entry_block(text::AbstractString, start_pos::Int)::Union{String,Nothing}
    depth = 0
    i = start_pos
    n = length(text)
    found_open = false

    while i <= n
        c = text[i]
        if c == '{'
            depth += 1
            found_open = true
        elseif c == '}'
            depth -= 1
            if found_open && depth == 0
                return text[start_pos:i]
            end
        end
        i = nextind(text, i)
    end
    return nothing
end
=#

"""
    parse_entry_block(block) -> Union{Dict{String,String}, Nothing}

Parse a single BibTeX entry block string into a dict of fields.
"""
function parse_entry_block(block::AbstractString)::Union{Dict{String,String},Nothing}
    # Match the entry type and key: @article{somekey,
    m = match(r"@(\w+)\s*\{\s*([^,\s]+)\s*,", block)
    isnothing(m) && return nothing

    entry = Dict{String,String}()
    entry["ENTRYTYPE"] = lowercase(m.captures[1])
    entry["ID"]        = strip(m.captures[2])

    # The fields start after the opening @type{key,
    fields_text = block[m.offset + length(m.match) : end-1]  # strip final }

    # Parse fields: fieldname = {value} or fieldname = "value" or fieldname = bare
    # Values in braces may be nested and span multiple lines.
    i = 1
    n = length(fields_text)

    while i <= n
        # Skip whitespace and commas
        while i <= n && (isspace(fields_text[i]) || fields_text[i] == ',')
            i = nextind(fields_text, i)
        end
        i > n && break

        # Read field name (letters, digits, underscores)
        name_match = match(r"^([a-zA-Z_]\w*)\s*=\s*", fields_text[i:end])
        isnothing(name_match) && break

        field_name = lowercase(name_match.captures[1])
        i += length(name_match.match)
        i > n && break

        # Read field value
        val, new_i = read_field_value(fields_text, i)
        entry[field_name] = val
        i = new_i
    end

    return entry
end

"""
    read_field_value(text, start) -> (String, Int)

Read a BibTeX field value starting at `start`. Handles:
- Brace-delimited values (possibly nested): {value {nested} more}
- Quote-delimited values: "value"
- Bare values (numbers or macros): 2024
Returns the raw value string and the index after the value.
"""
function read_field_value(text::String, start::Int)::Tuple{String,Int}
    n = length(text)
    start > n && return ("", start)

    c = text[start]

    if c == '{'
        # Brace-delimited: track depth
        depth = 0
        i = start
        val_start = start + 1   # content starts after opening brace
        while i <= n
            ch = text[i]
            if ch == '{'
                depth += 1
            elseif ch == '}'
                depth -= 1
                if depth == 0
                    val = text[val_start : prevind(text, i)]
                    return (val, nextind(text, i))
                end
            elseif ch == '\\' && i < n
                # Skip escaped character
                i = nextind(text, i)
            end
            i = nextind(text, i)
        end
        # Unterminated brace — return what we have
        return (text[val_start:end], n+1)

    elseif c == '"'
        # Quote-delimited
        i = nextind(text, start)
        val_start = i
        while i <= n
            ch = text[i]
            if ch == '"'
                val = text[val_start : prevind(text, i)]
                return (val, nextind(text, i))
            elseif ch == '\\'
                i = nextind(text, i)   # skip escaped char
            end
            i = nextind(text, i)
        end
        return (text[val_start:end], n+1)

    else
        # Bare value: read until comma, whitespace, or closing brace
        i = start
        while i <= n && !isspace(text[i]) && text[i] ∉ (',', '}')
            i = nextind(text, i)
        end
        return (text[start:prevind(text,i)], i)
    end
end

# ---------------------------------------------------------------------------
# Config loader
# ---------------------------------------------------------------------------

"""
    load_config(path) -> Dict{String,String}

Read a simple KEY = value config file.
"""
function load_config(path::String)::Dict{String,String}
    config = Dict{String,String}()
    isfile(path) || error("Config file not found: $path")
    for line in eachline(path)
        line = strip(line)
        isempty(line) && continue
        startswith(line, "#") && continue
        if contains(line, "=")
            key, _, val = partition(line, "=")
            config[strip(key)] = strip(val)
        end
    end
    return config
end

# ---------------------------------------------------------------------------
# ADS abstract fetching
# ---------------------------------------------------------------------------

"""
    fetch_abstract(bibcode, api_key; delay=0.5) -> String

Query the ADS API for the abstract of a paper identified by `bibcode`.
Returns an empty string on failure.
"""
function fetch_abstract(bibcode::String, api_key::String; delay::Float64=0.5)::String
    # Strip to bare bibcode if a full URL was passed
    bibcode = last(split(rstrip(bibcode, '/'), '/'))

    url = "https://api.adsabs.harvard.edu/v1/search/query"
    headers = ["Authorization" => "Bearer $api_key"]
    params  = "q=bibcode:$bibcode&fl=abstract&rows=1"

    sleep(delay)

    try
        resp = HTTP.get("$url?$params", headers)
        if resp.status == 200
            body = JSON3.read(String(resp.body))
            docs = get(get(body, :response, Dict()), :docs, [])
            if !isempty(docs) && haskey(docs[1], :abstract)
                abstract = string(docs[1][:abstract])
                abstract = expand_macros(abstract)
                abstract = latex_to_unicode(abstract)
                return abstract
            end
        else
            @warn "ADS API returned status $(resp.status) for $bibcode"
        end
    catch e
        @warn "Failed to fetch abstract for $bibcode: $e"
    end
    return ""
end

# ---------------------------------------------------------------------------
# Filename generation
# ---------------------------------------------------------------------------

"""
    first_author_last_name(author_string) -> String

Extract and sanitize the last name of the first author from an ADS author
string of the form "Last, First and Last, First and...".
"""
function first_author_last_name(author_string::String)::String
    first_author = split(author_string, " and ")[1]
    last_name    = split(first_author, ",")[1]
    last_name    = strip(last_name, ['{', '}', ' '])
    # Remove characters unsafe for filenames
    last_name    = replace(last_name, r"[^a-zA-Z0-9_\-]" => "")
    return isempty(last_name) ? "unknown" : last_name
end

"""
    assign_filenames(entries) -> Vector{String}

Assign filenames to all entries in one pass, correctly handling conflicts.
A single paper by Ford in 2024 → Ford_2024.toml.
Two papers → Ford_2024a.toml, Ford_2024b.toml.
"""
function assign_filenames(entries::Vector{Dict{String,String}})::Vector{String}
    # Count occurrences of each (lastname, year) key
    key_counts = Dict{Tuple{String,String}, Int}()
    for entry in entries
        last = first_author_last_name(get(entry, "author", "unknown"))
        year = clean_value(get(entry, "year", "0000"))
        key  = (last, year)
        key_counts[key] = get(key_counts, key, 0) + 1
    end

    # Assign filenames in order of appearance
    key_seen = Dict{Tuple{String,String}, Int}()
    filenames = String[]
    for entry in entries
        last = first_author_last_name(get(entry, "author", "unknown"))
        year = clean_value(get(entry, "year", "0000"))
        key  = (last, year)
        key_seen[key] = get(key_seen, key, 0) + 1

        suffix = key_counts[key] == 1 ? "" : string(Char(Int('a') + key_seen[key] - 1))
        push!(filenames, "$(last)_$(year)$(suffix).toml")
    end
    return filenames
end

# ---------------------------------------------------------------------------
# TOML writer
# ---------------------------------------------------------------------------

"""
    toml_string(s) -> String

Encode a string as a TOML basic string, escaping backslashes and quotes.
"""
function toml_string(s::AbstractString)::String
    s = replace(s, "\\" => "\\\\")
    s = replace(s, "\"" => "\\\"")
    return "\"$s\""
end

"""
    toml_multiline(s) -> String

Encode a string as a TOML multiline literal string using triple single-quotes.
Safe for abstracts which may contain backslashes, quotes, etc.
"""
function toml_multiline(s::AbstractString)::String
    # TOML literal strings cannot contain ''', so escape if needed
    s = replace(s, "'''" => "'''")
    return "'''\n$s\n'''"
end

"""
    write_publication_toml(path, entry, abstract)

Write a publication TOML file to `path` from a BibTeX entry dict and abstract.
"""
function write_publication_toml(path::AbstractString, entry::Dict{String,String}, abstract::AbstractString)
    mkpath(dirname(path))

    # Fields to write in order, with their cleaned values
    core_fields = [
        "title", "author", "year", "journal", "volume", "number",
        "pages", "month", "eid",
    ]
    id_fields = [
        "doi", "adsurl", "bibcode", "eprint",
        "archiveprefix", "primaryclass", "adsnote",
    ]

    open(path, "w") do io
        # Comment header with title for human readability
        title_clean = clean_value(get(entry, "title", ""))
        println(io, "# $title_clean\n")

        # Core bibliographic fields
        for key in core_fields
            val = get(entry, key, "")
            isempty(val) && continue
            cleaned = clean_value(val)
            isempty(cleaned) && continue
            println(io, "$(rpad(key, 16)) = $(toml_string(cleaned))")
        end

        # Identifier / metadata fields (stored raw, not cleaned)
        for key in id_fields
            val = strip(get(entry, key, ""), ['{', '}', ' '])
            isempty(val) && continue
            println(io, "$(rpad(key, 16)) = $(toml_string(val))")
        end

        # Entry type
        println(io, "$(rpad("entrytype", 16)) = $(toml_string(get(entry, "ENTRYTYPE", "article")))")

        # Abstract as multiline literal
        println(io, "\nabstract         = $(toml_multiline(abstract))")

        # Placeholder arrays for manual curation
        println(io, "\ntags             = [\"\"]")
        println(io, "research_themes  = [\"\"]")
    end
end

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

"""
    parse_args() -> NamedTuple

Parse command-line arguments.
"""
function parse_args()
    bibfile   = ""
    config    = ".ads_config"
    outdir    = "_data/publications"
    dry_run   = false
    skip_ads  = false
    delay     = 0.5

    args = copy(ARGS)
    isempty(args) && usage()

    bibfile = popfirst!(args)
    (!isfile(bibfile)) && error("BibTeX file not found: $bibfile")

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--config" && i < length(args)
            config = args[i+1]; i += 2
        elseif arg == "--outdir" && i < length(args)
            outdir = args[i+1]; i += 2
        elseif arg == "--delay" && i < length(args)
            delay = parse(Float64, args[i+1]); i += 2
        elseif arg == "--dry-run"
            dry_run = true; i += 1
        elseif arg == "--skip-ads"
            skip_ads = true; i += 1
        else
            @warn "Unknown argument: $arg"
            i += 1
        end
    end

    return (
        bibfile  = bibfile,
        config   = config,
        outdir   = outdir,
        dry_run  = dry_run,
        skip_ads = skip_ads,
        delay    = delay,
    )
end

function usage()
    println("""
Usage:
    julia --project=scripts/parse_publications \\
          scripts/parse_publications/parse_publications.jl <file.bib> [options]

Options:
    --config <path>    Path to.ads_config file (default:.ads_config)
    --outdir <path>    Output directory root (default: _data/publications)
    --delay <secs>     Delay between ADS API calls (default: 0.5)
    --skip-ads         Skip ADS abstract fetching entirely
    --dry-run          Parse and report without writing files or calling ADS
""")
    exit(1)
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function main()
    args = parse_args()

    # Load API key unless we won't need it
    api_key = ""
    if !args.skip_ads && !args.dry_run
        config  = load_config(args.config)
        api_key = get(config, "ADS_API_KEY", "")
        if isempty(api_key)
            error("ADS_API_KEY not found in $(args.config)")
        end
    end

    println("Parsing $(args.bibfile)...")
    bib_text = read(args.bibfile, String)
    entries  = parse_bibtex(bib_text)
    println("Found $(length(entries)) entries.\n")

    filenames = assign_filenames(entries)

    for (entry, filename) in zip(entries, filenames)
        year      = clean_value(get(entry, "year", "0000"))
        out_path  = joinpath(args.outdir, year, filename)
        title     = clean_value(get(entry, "title", "(no title)"))
        short_title = length(title) > 72 ? title[1:72] * "..." : title

        println("  $filename")
        println("    Title:  $short_title")

        if args.dry_run
            println("    [dry-run] would write to $out_path\n")
            continue
        end

        # Fetch abstract
        abstract = ""
        if !args.skip_ads
            adsurl  = strip(get(entry, "adsurl", ""), ['{', '}', ' '])
            bibcode = strip(get(entry, "bibcode", ""), ['{', '}', ' '])
            # Fall back to extracting bibcode from adsurl
            if isempty(bibcode) && !isempty(adsurl)
                bibcode = last(split(rstrip(adsurl, '/'), '/'))
            end
            if !isempty(bibcode)
                println("    Fetching abstract for $bibcode...")
                abstract = fetch_abstract(bibcode, api_key; delay=args.delay)
                isempty(abstract) && println("    Warning: no abstract returned.")
            else
                println("    Warning: no bibcode found, skipping abstract.")
            end
        else
            println("    [skip-ads] abstract not fetched.")
        end

        write_publication_toml(out_path, entry, abstract)
        println("    Written: $out_path\n")
    end

    println("Done!")
end

main()