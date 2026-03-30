<!--
  Franklin.jl configuration for Eric B. Ford's personal website
-->

@def author      = "Eric B. Ford"
@def mintoclevel  = 2
@def maxtoclevel  = 3
@def prepath      = ""
@def website_title = "Eric B. Ford"
@def website_descr = "Distinguished Professor of Astronomy & Astrophysics, Penn State University"
@def website_url   = "https://eford.netlify.app"

<!-- Navigation bar items -->
+++
nav_items = [
  "Home" =>         "/",
  "Research" =>     "/research/",
  "Publications" => "/publications/",
  "Teaching" =>     "/teaching/",
  "Group" =>        "/group/",
  "Software" =>     "/software/",
  "Contact" =>      "/contact/" ]
+++

<!-- RSS -->
@def generate_rss = true
@def rss_title    = "Eric B. Ford"
@def rss_descr    = "Research updates from Eric B. Ford"
@def rss_full_content = false

<!-- Code evaluation (off by default) -->
@def showall = false

<!-- Date format -->
@def date_format = "U d, yyyy"
