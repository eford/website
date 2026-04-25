#!/usr/bin/env julia
# Import BibTeX entries and generate Franklin-compatible publication pages
# Usage: julia --project=. scripts/import_bibtex.jl path/to/refs.bib
#
# Requires: BibParser.jl
# Pkg.add("BibParser")

using Pkg
Pkg.activate(".")

try
    using BibParser
catch
    Pkg.add("BibParser")
    using BibParser
end

function bibtex_to_franklin(bibfile::String; outdir="publications")
    entries = BibParser.parse_file(bibfile)

    mkpath(outdir)

    for (key, entry) in entries
        title   = get(entry, "title", "Untitled")
        authors = get(entry, "author", "")
        year    = get(entry, "year", "")
        journal = get(entry, "journal", get(entry, "booktitle", ""))
        volume  = get(entry, "volume", "")
        pages   = get(entry, "pages", "")
        doi     = get(entry, "doi", "")
        arxiv   = get(entry, "eprint", "")

        slug = replace(lowercase(key), r"[^a-z0-9]" => "-")
        filepath = joinpath(outdir, "$slug.md")

        open(filepath, "w") do io
            println(io, "@def title = \"$(replace(title, "\"" => "\\\""))\"")
            println(io, "@def authors = \"$authors\"")
            println(io, "@def year = \"$year\"")
            println(io, "@def journal = \"$journal\"")
            println(io, "@def tags = [\"publication\"]")
            println(io, "")
            println(io, "# $title")
            println(io, "")
            println(io, "**Authors:** $authors")
            println(io, "")
            !isempty(journal) && println(io, "**Journal:** $journal $(isempty(volume) ? "" : "**$volume**") $(isempty(pages) ? "" : ", $pages") ($year)")
            println(io, "")
            !isempty(doi) && println(io, "**DOI:** [$(doi)](https://doi.org/$(doi))")
            !isempty(arxiv) && println(io, "**arXiv:** [$arxiv](https://arxiv.org/abs/$arxiv)")
        end

        println("  ✅ Generated: $filepath")
    end

    println("\nDone! Generated $(length(entries)) publication pages in $outdir/")
end

if length(ARGS) >= 1
    bibtex_to_franklin(ARGS[1])
else
    println("Usage: julia scripts/import_bibtex.jl path/to/refs.bib")
end
