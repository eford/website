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
            """    <a href="$(l["url"])" title="$(l["title"])"><i class="$(l["icon"])"></i></a>"""
            for l in links
        ], "\n")
        "  <p>\n$inner\n  </p>\n"
    else
        ""
    end

    bio_html = isempty(bio) ? "" : "  <p>$bio</p>\n"

    return """<div class="member-card">
  <img src="$image" alt="$name" class="member-image">
  <div class="member-text">
  <$hlevel><a href="$profile_url">$display</a></$hlevel>
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


