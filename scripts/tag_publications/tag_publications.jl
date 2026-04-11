#!/usr/bin/env julia

# update_publications.jl
#
# Usage:
#   julia update_publications.jl <publications_dir> <tags_file> [--dry-run]
#
# Recursively scans <publications_dir> for.toml files, uses an LLM to suggest
# tags and research_themes from a provided list, and merges them into each file.
# Optionally suggested new tags/themes are appended as comments.

using TOML
using JSON3
using PromptingTools
using OrderedCollections
using Logging

const PT = PromptingTools

# ── Helpers ───────────────────────────────────────────────────────────────────

function load_tag_list(path::String)
    lines = readlines(path)
    # Strip blank lines and comment lines (starting with #)
    return [strip(l) for l in lines if !isempty(strip(l)) && !startswith(strip(l), "#")]
end

function find_toml_files(dir::String)
    toml_files = String[]
    for (root, dirs, files) in walkdir(dir)
        for file in files
            if endswith(file, ".toml")
                push!(toml_files, joinpath(root, file))
            end
        end
    end
    return sort(toml_files)
end

# ── TOML Parsing into OrderedDict ─────────────────────────────────────────────

# TOML.parse returns plain Dicts; this recursively converts them to OrderedDicts
# so that TOML.print preserves the original key order.
function to_ordered(d::Dict)
    #return OrderedDict(d)
    
    od = OrderedDict{String, Any}()
    std_keys = [ "title", "author", "year", "month", "journal", "volume", "number", "pages", "doi", "adsurl", "archiveprefix", "eprint", "primaryclass", "entrytype", "abstract", "tags", "research_themes"]
    extra_keys = setdiff(keys(d), std_keys)
    
    for k in [std_keys...,   extra_keys...]  # Dict has no guaranteed order, but keys() reflects insertion
        if haskey(d, k)
            od[k] = to_ordered(d[k])
        end
    end
    return od
end
to_ordered(v::Vector) = [to_ordered(x) for x in v]
to_ordered(x)         = x  # scalars pass through unchanged

function parse_toml_ordered(path::String)
    raw = read(path, String)
    d   = TOML.parse(raw)
    return to_ordered(d), raw
end

# ── Prompt ────────────────────────────────────────────────────────────────────

function build_prompt_json(title::AbstractString, abstract::AbstractString, tag_list::Vector{<:AbstractString}, theme_list::Vector{<:AbstractString})
    tags_formatted = join(tag_list, "\n  - ") 
    themes_formatted = join(theme_list, "\n  - ") 
    return """
    You are a research librarian helping to tag academic publications.

    Given the publication title and abstract below, do two things:

    1. SELECT tags and research themes from the APPROVED LISTS that are relevant.
       Only choose items that clearly apply — do not over-tag.

    2. SUGGEST any additional tags NOT in the approved list
       that you think would be valuable. Keep suggestions concise and specific.

    ## Publication
    Title: $title

    Abstract: $abstract

    ## Approved Tags List
      - $tags_formatted

    ## Approved Themes List
      - $themes_formatted

    ## Response Format
    Respond ONLY with a valid JSON file that contains exactly three keys. 
    No explanation.  No markdown fences.  
    
    Example:
    {
      "selected_tags": ["tag one", "tag two"],
      "selected_research_themes": ["theme one"],
      "suggested_new_tags": ["novel tag"],
    }

    Use empty arrays if nothing applies. Every key must be present.  Do not use nested arrays.  
    """
end

#=
    selected_tags = ["tag one", "tag two"]
    selected_research_themes = ["theme one"]
    suggested_new_tags = ["novel tag"]
      "suggested_new_research_themes": ["novel theme"]
=#

# ── LLM Call ─────────────────────────────────────────────────────────────────

function query_llm(prompt::AbstractString; model::AbstractString = "gemma3:1b")
    if model == "claude"
        schema = PT.AnthropicSchema() 
    else
        schema = PT.OllamaSchema() 
    end
    response = PT.aigenerate(schema, String(prompt); model = String(model), verbose = false)
    return PT.last_output(response)
end

function parse_llm_response_toml(raw::AbstractString)
    # Strip markdown fences if the model ignores instructions
    cleaned = replace(raw, r"```[a-z]*\n?" => "", r"```" => "")
    try
        return TOML.parse(cleaned)
    catch e
        @warn "Failed to parse LLM response as TOML" exception=e raw=raw
        return nothing
    end
end


function parse_llm_response_json(raw::AbstractString)
    # Strip markdown fences if the model ignores instructions
    cleaned = strip(replace(raw, r"```json\s*"i => "", r"```" => ""))

    # Extract the first {...} block in case the model adds surrounding text
    m = match(r"\{.*\}"s, cleaned)
    if isnothing(m)
        @warn "No JSON object found in LLM response" raw=raw
        return nothing
    end

    try
        parsed = JSON3.read(m.match)

        # Validate that all expected keys are present
        required_keys = (:selected_tags, :selected_research_themes,
                         :suggested_new_tags ) #, :suggested_new_research_themes)
        missing_keys = [k for k in required_keys if !haskey(parsed, k)]
        if !isempty(missing_keys)
            @warn "LLM response missing expected keys" missing=missing_keys
        end

        # Convert to plain Dict{String, Vector{String}} for consistent downstream use
        return OrderedDict{String, Vector{String}}(
            "selected_tags"                  => collect(get(parsed, :selected_tags, [])),
            "selected_research_themes"       => collect(get(parsed, :selected_research_themes, [])),
            "suggested_new_tags"             => collect(get(parsed, :suggested_new_tags, []))
            #"suggested_new_research_themes"  => collect(get(parsed, :suggested_new_research_themes, []))
        )
    catch e
        @warn "Failed to parse LLM response as JSON" exception=e raw=raw
        return nothing
    end
end

# ── Core Logic ────────────────────────────────────────────────────────────────

function process_file(path::AbstractString, tag_list::Vector{<:AbstractString}, theme_list::Vector{<:AbstractString}; dry_run::Bool = false, model::AbstractString = "claude")
    @info "Processing: $path"

    data, _ = parse_toml_ordered(path)

    title    = get(data, "title", "")
    abstract = get(data, "abstract", "")

    if isempty(title) && isempty(abstract)
        @warn "  Skipping — no title or abstract found."
        return
    end

    # Merge with existing values (deduplicated)
    existing_tags   = get(data, "tags", String[])
    existing_themes = get(data, "research_themes", String[])
    
    if (length(existing_tags) > 1) || (length(existing_tags)==1 && length(first(existing_tags))>0)
        println("  [SKIP] Has existing tags: ", existing_tags)
        return
    end
    
    # Query the LLM
    prompt = build_prompt_json(title, abstract, tag_list, theme_list)
    raw_response = try
        query_llm(prompt; model = model)
    catch e
        @error "  LLM call failed" exception=e
        return
    end

    parsed = parse_llm_response_json(raw_response)
    if isnothing(parsed)
        @warn "  Skipping — could not parse LLM response."
        return
    end

    # Extract LLM results (default to empty arrays on missing keys)
    selected_tags     = get(parsed, "selected_tags", String[])
    selected_themes   = get(parsed, "selected_research_themes", String[])
    suggested_tags    = get(parsed, "suggested_new_tags", String[])
    suggested_themes  = selected_themes # get(parsed, "suggested_new_research_themes", String[])

    merged_tags   = collect(Set([existing_tags...,   selected_tags...]))
    merged_themes = collect(Set([existing_themes..., selected_themes...]))

    # Sort for stable output
    if length(merged_tags)>= 2
        sort!(merged_tags)
    end
    if length(merged_themes)>= 2
        sort!(merged_themes)
    end

    if existing_tags == [""]
        existing_tags = String[]
    end
    if existing_themes == [""]
        existing_themes = String[]
    end
    
    # Report
    new_tags   = setdiff(Set(selected_tags),   Set(existing_tags))
    new_themes = setdiff(Set(selected_themes), Set(existing_themes))

    println("  ┌─ Selected tags added    : ", isempty(new_tags)   ? "(none new)" : join(new_tags,   ", "))
    println("  ├─ Selected themes added  : ", isempty(new_themes) ? "(none new)" : join(new_themes, ", "))
    println("  ├─ Suggested new tags     : ", isempty(suggested_tags)   ? "(none)" : join(suggested_tags,   ", "))
    #println("  └─ Suggested new themes   : ", isempty(suggested_themes) ? "(none)" : join(suggested_themes, ", "))

    if dry_run
        println("  [DRY RUN] No changes written.")
        return
    end

    # Update the data dict
    data["tags"]             = merged_tags
    data["research_themes"]  = merged_themes

    # Build the new TOML string, appending suggestions as comments
    buf = IOBuffer()
    TOML.print(buf, data)
    toml_str = String(take!(buf))

    # Append suggestions as a comment block at the end of the file
    if !isempty(suggested_tags) || !isempty(suggested_themes)
        toml_str *= "\n"
        toml_str *= "# ── LLM-suggested additions (not in approved list) ──────────────────────────\n"
        if !isempty(suggested_tags)
            #= toml_str *= "# suggested_tags = " * TOML.print(Dict("x" => suggested_tags)) |> 
                        s -> match(r"x = (.+)", s).match |> 
                        s -> replace(s, "x = " => "") |> strip
                        =#
            # Simpler inline approach:
            toml_str *= "# suggested_tags             = [" * join(["\"$t\"" for t in suggested_tags], ", ") * "]\n"
        end
        if !isempty(suggested_themes)
            toml_str *= "# suggested_research_themes  = [" * join(["\"$t\"" for t in suggested_themes], ", ") * "]\n"
        end
    end

    write(path, toml_str)
    @info "  ✓ Updated."
end

# ── Entry Point ───────────────────────────────────────────────────────────────

function main()
    args = ARGS

    if length(args) < 2
        println("""
        Usage:
          julia update_publications.jl <publications_dir> <tags_file> <themes_file> [--dry-run] [--model=<name>]

        Options:
          --dry-run          Print proposed changes without writing to disk
          --model=<name>     PromptingTools model alias (default: claude)
                             Examples: claude, gpt4o, ollama/mistral
        """)
        exit(1)
    end

    pub_dir   = args[1]
    tags_file = args[2]
    themes_file = args[3]
    dry_run   = "--dry-run" in args
    model     = "claude"  # default

    for arg in args
        if startswith(arg, "--model=")
            model = split(arg, "=")[2]
        end
    end

    if !isdir(pub_dir)
        @error "Publications directory not found: $pub_dir"
        exit(1)
    end
    if !isfile(tags_file)
        @error "Tags file not found: $tags_file"
        exit(1)
    end

    tag_list = load_tag_list(tags_file)
    @info "Loaded $(length(tag_list)) tags from $tags_file"

    theme_list = load_tag_list(themes_file)
    @info "Loaded $(length(theme_list)) themes from $themes_file"

    toml_files = find_toml_files(pub_dir)
    @info "Found $(length(toml_files)) TOML files in $pub_dir"

    dry_run && @info "DRY RUN MODE — no files will be modified"

    for (i, path) in enumerate(toml_files)
        println("\n[$i/$(length(toml_files))]")
        process_file(path, tag_list, theme_list; dry_run = dry_run, model = model)
        #break
    end

    println("\n✓ Done. $(length(toml_files)) files processed.")
end

main()
