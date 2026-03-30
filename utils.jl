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
