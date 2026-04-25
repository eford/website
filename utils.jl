# Franklin utility functions

"""
    hfun_bar(vname)
Simple helper: wraps content in a styled bar.
"""
function hfun_bar(vname)
    val = Meta.parse(vname[1])
    return "<strong>$val</strong>"
end

"""
    hfun_m1fill(vname)
Fill in a value from page variables.
"""
function hfun_m1fill(vname)
    var = vname[1]
    return Franklin.pagevar(Franklin.GLOBAL_LXDEFS, var)
end

"""
    hfun_member_card(params)
Generate an HTML card for a group member.
"""
function hfun_member_card(params)
    name  = params[1]
    role  = params[2]
    desc  = params[3]
    link  = length(params) >= 4 ? params[4] : ""
    img   = length(params) >= 5 ? params[5] : "/assets/images/placeholder.png"
    s = """
    <div class="member-card">
      <div class="member-info">
        <h3>$(isempty(link) ? name : "<a href=\"$link\">$name</a>")</h3>
        <p class="member-role">$role</p>
        <p>$desc</p>
      </div>
    </div>
    """
    return s
end


using TOML

# ---------------------------------------------------------------------------
# Core HTML builder
# ---------------------------------------------------------------------------

"""
    member_card_html(data) -> String

Generate the HTML for a single member card from a parsed TOML dict.
"""
function member_card_html(data::Dict)
    name        = get(data, "name", "")
    display     = get(data, "display_name", name)
    image       = get(data, "image", "")
    profile_url = get(data, "profile_url", "")
    role        = get(data, "role", "")
    role_html = replace(role, "\n" => "<br>")
    bio         = get(data, "bio", "")
    hlevel      = get(data, "heading_level", "h3")
    links       = get(data, "links", [])

    links_html = if !isempty(links)
        inner = join([
            # aria-label is the reliable accessible name for icon-only links (WCAG 1.1.1 / 4.1.2)
            """    <a href="$(l["url"])" aria-label="$(l["title"])" title="$(l["title"])"><i class="$(l["icon"])"></i></a>"""
            for l in links
        ], "\n")
        "  <p>\n$inner\n  </p>\n"
    else
        ""
    end

    bio_html = isempty(bio) ? "" : "  <p>$bio</p>\n"

    # WCAG 2.4.4 — only wrap in <a> when a url is actually present; empty href
    # resolves to the current page and creates a confusingly-named in-page link.
    name_html = isempty(profile_url) ? display : """<a href="$profile_url">$display</a>"""

    return """<div class="member-card">
  <img src="$image" alt="$name" class="member-image">
  <div class="member-text">
  <$hlevel>$name_html</$hlevel>
  <p class="member-role">$role_html</p>
$bio_html$links_html  </div>
</div>
"""
end

# ---------------------------------------------------------------------------
# hfun: explicit list of slugs
# ---------------------------------------------------------------------------

"""
    hfun_member_cards(params) -> String

Render member cards for an explicit list of TOML slugs.

Usage in .md:
    {{member_cards anne_dattilo rachel_fernandes laura_flagg}}

Each slug maps to `_data/members/<slug>.toml`.
"""
function hfun_member_cards(params)
    io = IOBuffer()
    for slug in params
        path = joinpath("_data", "members", "$slug.toml")
        if isfile(path)
            data = TOML.parsefile(path)
            write(io, member_card_html(data))
        else
            @warn "hfun_member_cards: file not found — $path"
        end
    end
    return String(take!(io))
end

# ---------------------------------------------------------------------------
# hfun: auto-load an entire subdirectory
# ---------------------------------------------------------------------------

"""
    hfun_member_cards_from_dir(params) -> String

Render all member cards found in a subdirectory of `_data/members/`.
Files are sorted lexicographically, so prefix filenames with `01_`, `02_`,
etc. to control order, or add a `sort_order` integer field to each TOML
(files with lower `sort_order` appear first; ties broken by filename).

Usage in .md:
    {{member_cards_from_dir postdocs}}

Maps to `_data/members/postdocs/*.toml`.
"""
function hfun_member_cards_from_dir(params; reverse::Bool = false)
    isempty(params) && return ""
    dir = joinpath("_data", "members", params[1])
    if !isdir(dir)
        @warn "hfun_member_cards_from_dir: directory not found — $dir"
        return ""
    end

    toml_files = filter(f -> endswith(f, ".toml"), readdir(dir))
    isempty(toml_files) && return ""

    # Parse all files first so we can sort by optional sort_order field
    entries = map(toml_files) do f
        path = joinpath(dir, f)
        data = TOML.parsefile(path)
        order = get(data, "sort_order", 999)
        (order, f, data)
    end

    sort!(entries, by = e -> (e[1], e[2]), rev=reverse)   # primary: sort_order, secondary: filename

    io = IOBuffer()
    for (_, _, data) in entries
        write(io, member_card_html(data))
    end
    return String(take!(io))
end

function hfun_member_cards_from_dir_reverse(params)
    hfun_member_cards_from_dir(params; reverse=true)
end


# ---------------------------------------------------------------------------
# Course card HTML builder
# ---------------------------------------------------------------------------

"""
    course_card_html(data) -> String

Generate the HTML for a single course card from a parsed TOML dict.
"""
function course_card_html(data::Dict)
    title       = get(data, "title", "")
    emoji       = get(data, "emoji", "")
    meta        = get(data, "meta", "")
    description = get(data, "description", "")
    archive_url = get(data, "archive_url", "")
    archive_label = get(data, "archive_label", "Course website & materials")

    heading = isempty(emoji) ? title : "$emoji $title"

    
    archive_html = if !isempty(archive_url)
        """  <p>📎 Archived <a href="$archive_url">$archive_label</a></p>\n"""
    else
        ""
    end
    
    return """<div class="course-card">
  <h3>$heading</h3>
  <p class="course-meta">$meta</p>
  <p>$description</p>
$archive_html</div>
"""
end

# ---------------------------------------------------------------------------
# hfun: explicit list of slugs
# ---------------------------------------------------------------------------

"""
    hfun_course_cards(params) -> String

Render course cards for an explicit list of TOML slugs.

Usage in .md:
    {{course_cards astro_140 astro_416 astro_528}}

Each slug maps to `_data/courses/<slug>.toml`.
"""
function hfun_course_cards(params)
    io = IOBuffer()
    for slug in params
        path = joinpath("_data", "courses", "$slug.toml")
        if isfile(path)
            data = TOML.parsefile(path)
            write(io, course_card_html(data))
        else
            @warn "hfun_course_cards: file not found — $path"
        end
    end
    return String(take!(io))
end

# ---------------------------------------------------------------------------
# hfun: auto-load an entire subdirectory
# ---------------------------------------------------------------------------

"""
    hfun_course_cards_from_dir(params) -> String

Render all course cards found in a subdirectory of `_data/courses/`.
Files are sorted by optional `sort_order` field, then by filename.
Prefix filenames with `01_`, `02_`, etc. to control order.

Usage in .md:
    {{course_cards_from_dir psu_recent}}

Maps to `_data/courses/psu_recent/*.toml`.
"""
function hfun_course_cards_from_dir(params)
    isempty(params) && return ""
    dir = joinpath("_data", "courses", params[1])
    if !isdir(dir)
        @warn "hfun_course_cards_from_dir: directory not found — $dir"
        return ""
    end

    toml_files = filter(f -> endswith(f, ".toml"), readdir(dir))
    isempty(toml_files) && return ""

    entries = map(toml_files) do f
        path = joinpath(dir, f)
        data = TOML.parsefile(path)
        order = get(data, "sort_order", 999)
        (order, f, data)
    end

    sort!(entries, by = e -> (e[1], e[2]))

    io = IOBuffer()
    for (_, _, data) in entries
        write(io, course_card_html(data))
    end
    return String(take!(io))
end


# ---------------------------------------------------------------------------
# Software card HTML builder
# ---------------------------------------------------------------------------

"""
    software_card_html(data) -> String

Generate the HTML for a single software card from a parsed TOML dict.
"""
function software_card_html(data::Dict)
    name        = get(data, "name", "")
    url         = get(data, "url", "")
    description = get(data, "description", "")

    name_html = isempty(url) ? name : """<a href="$url">$name</a>"""

    return """  <div class="card">
    <h3>$name_html</h3>
    <p>$description</p>
  </div>
"""
end

# ---------------------------------------------------------------------------
# hfun: explicit list of slugs
# ---------------------------------------------------------------------------

"""
    hfun_software_cards(params) -> String

Render software cards for an explicit list of TOML slugs, wrapped in a
card-grid div.

Usage in .md:
    {{software_cards exoplanetssyssim symsimexclusters}}

Each slug maps to `_data/software/<slug>.toml`.
"""
function hfun_software_cards(params)
    io = IOBuffer()
    write(io, """<div class="card-grid">\n""")
    for slug in params
        path = joinpath("_data", "software", "$slug.toml")
        if isfile(path)
            data = TOML.parsefile(path)
            write(io, software_card_html(data))
        else
            @warn "hfun_software_cards: file not found — $path"
        end
    end
    write(io, "</div>\n")
    return String(take!(io))
end

# ---------------------------------------------------------------------------
# hfun: auto-load an entire subdirectory
# ---------------------------------------------------------------------------

"""
    hfun_software_cards_from_dir(params) -> String

Render all software cards found in a subdirectory of `_data/software/`,
wrapped in a card-grid div. Files are sorted by `sort_order` field (required),
then by filename as a tiebreaker.

Usage in .md:
    {{software_cards_from_dir demographics}}

Maps to `_data/software/demographics/*.toml`.
"""
function hfun_software_cards_from_dir(params)
    isempty(params) && return ""
    dir = joinpath("_data", "software", params[1])
    if !isdir(dir)
        @warn "hfun_software_cards_from_dir: directory not found — $dir"
        return ""
    end

    toml_files = filter(f -> endswith(f, ".toml"), readdir(dir))
    isempty(toml_files) && return ""

    entries = map(toml_files) do f
        path = joinpath(dir, f)
        data = TOML.parsefile(path)
        order = get(data, "sort_order", 999)
        (order, f, data)
    end

    sort!(entries, by = e -> (e[1], e[2]))

    io = IOBuffer()
    write(io, """<div class="card-grid">\n""")
    for (_, _, data) in entries
        write(io, software_card_html(data))
    end
    write(io, "</div>\n")
    return String(take!(io))
end




# ---------------------------------------------------------------------------
# Publication citation builder
# ---------------------------------------------------------------------------

"""
    escape_attr(s) -> String

Escape a string for safe use inside an HTML attribute value (double-quoted).
"""
function escape_attr(s::String)::String
    s = replace(s, "&"  => "&amp;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "<"  => "&lt;")
    s = replace(s, ">"  => "&gt;")
    return s
end

"""
    format_authors(author_string) -> String

Parse an ADS-format author string ("Last, F. I. and Last, F. I. and...")
and return a formatted string. If more than 3 authors, returns "Last, F. I. et al."
"""
function format_authors(author_string::String)
    isempty(author_string) && return ""
    authors = strip.(split(author_string, " and "))
    if length(authors) <= 3
        return join(authors, ", ")
    else
        return "$(authors[1]) et al."
    end
end

"""
    format_citation(data) -> String

Generate a formatted HTML citation string from a publication TOML dict.

Format:
    <strong>Title</strong>
    Author(s) (Year), <em>Journal</em>, Volume, Pages.
    <a href=adsurl>abstract</a> <a href=doi>doi</a>
"""
function format_citation(data::Dict)::String
    title   = get(data, "title",   "")
    authors = get(data, "author",  "")
    year    = get(data, "year",    "")
    journal = get(data, "journal", "")
    volume  = get(data, "volume",  "")
    pages   = get(data, "pages",   "")
    adsurl  = get(data, "adsurl",  "")
    doi     = get(data, "doi",     "")

    author_str = format_authors(authors)

    # Build the journal info segment, omitting missing fields
    journal_parts = String[]
    !isempty(journal) && push!(journal_parts, "<em>$journal</em>")
    !isempty(volume)  && push!(journal_parts, volume)
    !isempty(pages)   && push!(journal_parts, pages)
    journal_str = join(journal_parts, ", ")

    # Build the main citation line
    byline_parts = String[]
    !isempty(author_str) && push!(byline_parts, author_str)
    !isempty(year)       && push!(byline_parts, "($year)")
    citation_line = join(byline_parts, " ")
    !isempty(journal_str) && (citation_line *= ", $journal_str.")

    # Append links — aria-label gives screen-reader users the full context
    # (WCAG 2.4.4: link purpose determinable from link text alone)
    title_attr = escape_attr(title)
    !isempty(adsurl) && (citation_line *= """ <a href="$adsurl" aria-label="Abstract for $title_attr">abstract</a>""")
    !isempty(doi)    && (citation_line *= """ <a href="https://doi.org/$doi" aria-label="DOI for $title_attr">doi</a>""")

    # Use <span class="pub-title"> rather than <strong>: bold is visual styling
    # here, not a semantic importance signal (WCAG / HTML semantics best practice)
    return """<span class="pub-title">$title</span><br>\n$citation_line"""
end

"""
    hfun_pub(params) -> String

Render a single publication citation from a TOML file.

Usage in.md:
    {{pub 2024 Ford_2024}}

First parameter:  year
Second parameter: filename (without.toml extension)
"""
function hfun_pub(params)
    length(params) == 1 || error("hfun_pub requires exactly one parameter: filename (LastName_Year[a], excluding .toml suffix")
    filename     = params[1]
    m = match(r"\w+_(\d+)\w?$",filename)
    if length(m.captures) == 1
        year = first(m.captures)
    else
        @warn "hfun_pub: failed to extract filesname from $params"
        return ""
    end
    path     = joinpath("_data", "publications", year, filename * ".toml")
    if !isfile(path)
        @warn "hfun_pub: file not found — $path"
        return ""
    end
    data = TOML.parsefile(path)
    return "<p> " * format_citation(data) * " </p>"
end

# ---------------------------------------------------------------------------
# Publication loading and filtering
# ---------------------------------------------------------------------------

"""
    load_publications(pub_dir) -> Vector{Dict}

Read all TOML files from `_data/publications/` (recursing into year
subdirectories) and return them as a vector of dicts, each augmented with
a `_path` key for debugging.
"""
function load_publications(pub_dir::String = "_data/publications")::Vector{Dict}
    pubs = Dict[]
    isdir(pub_dir) || return pubs
    for (root, dirs, files) in walkdir(pub_dir)
        sort!(dirs)
        for f in sort(files)
            endswith(f, ".toml") || continue
            path = joinpath(root, f)
            data = TOML.parsefile(path)
            data["_path"] = path
            push!(pubs, data)
        end
    end
    return pubs
end

"""
    filter_publications(pubs, research_theme; tags=[]) -> Vector{Dict}

Filter a vector of publication dicts.

- `research_theme`: required string; publication must include it in its
  `research_themes` array (case-insensitive).
- `tags`: optional vector of strings; if non-empty, the publication must
  match at least one tag (OR logic, case-insensitive).
"""
function filter_publications(
    pubs::Vector{Dict},
    research_theme::String;
    tags::Vector{String} = String[]
)::Vector{Dict}
    theme_lc = lowercase(strip(research_theme))
    tags_lc  = lowercase.(strip.(tags))

    return filter(pubs) do pub
        # Check research_theme (required)
        pub_themes = lowercase.(strip.(get(pub, "research_themes", String[])))
        theme_match = any(t -> t == theme_lc, pub_themes)
        !theme_match && return false

        # Check tags (optional; OR logic)
        isempty(tags_lc) && return true
        pub_tags = lowercase.(strip.(get(pub, "tags", String[])))
        return any(tag -> tag in pub_tags, tags_lc)
    end
end

"""
    sort_publications_by_year(pubs) -> Vector{Dict}

Sort publications newest-first by year, then alphabetically by
first author within the same year.
"""
function sort_publications_by_year(pubs::Vector{Dict})::Vector{Dict}
    return sort(pubs, by = p -> (
        -parse(Int, get(p, "year", "0")),
         get(p, "author", "")
    ))
end

# ---------------------------------------------------------------------------
# hfun: filtered publication list
# ---------------------------------------------------------------------------

"""
    hfun_publication_list(params) -> String

Render an HTML bulleted list of formatted citations filtered by research
theme and optionally by tags.

Usage in.md:
    {{publication_list exoplanet_demographics}}
    {{publication_list radial_velocity neid eprv}}

First parameter:  research_theme (required)
Remaining params: tags (optional, OR logic)
"""
function hfun_publication_list(params)
    isempty(params) && return ""

    research_theme = replace(params[1], "_" => " ")
    tags = length(params) > 1 ?
        [replace(p, "_" => " ") for p in params[2:end]] :
        String[]

    pubs    = load_publications()
    matched = filter_publications(pubs, research_theme; tags=tags)
    sorted  = sort_publications_by_year(matched)

    if isempty(sorted)
        return "<p><em>No publications found matching the specified theme/tags.</em></p>\n"
    end

    # aria-label distinguishes multiple publication lists on the same page
    # when a screen-reader user navigates by list landmarks (WCAG usability)
    theme_label = escape_attr(titlecase(research_theme))
    io = IOBuffer()
    write(io, """<ul aria-label="Publications: $theme_label">\n""")
    for pub in sorted
        citation = format_citation(pub)
        write(io, "  <li>$citation</li>\n")
    end
    write(io, "</ul>\n")
    return String(take!(io))
end
