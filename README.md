# Eric B. Ford — Personal Academic Website

Built with [Franklin.jl](https://franklinjl.org/), a static site generator for Julia.

## Quick Start

```bash
# Install Julia (1.10+), then:
cd eford-website
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Live preview with hot reload:
julia --project=. -e 'using Franklin; serve()'

# Or use the helper script:
julia --project=. scripts/build_local.jl --serve
```

Open http://localhost:8000 in your browser.
Production Build
```bash
julia --project=. -e 'using Franklin; optimize()'
```

The optimized site is generated in __site/.
Deployment
Netlify (recommended)
The netlify.toml is pre-configured. Connect your GitHub repo to Netlify and it will auto-deploy on push.
GitHub Actions
Set NETLIFY_AUTH_TOKEN and NETLIFY_SITE_ID as repository secrets. The .github/workflows/deploy.yml handles CI/CD.

Directory Structure  
├── config.md           # Site-wide configuration
├── utils.jl            # Franklin helper functions
├── index.md            # Landing page
├── research/           # Research overview
├── publications/       # Publication list
├── teaching/           # Courses
├── group/              # Research group members
├── software/           # Open-source software
├── contact/            # Contact information
├── _layout/            # HTML templates (head, nav, footer)
├── _css/               # Stylesheets
├── _assets/            # Images and static files
├── scripts/            # Build and import utilities
├── netlify.toml        # Netlify deployment config
└── .github/workflows/  # GitHub Actions CI/CD

Adding Content

Edit Markdown files directly
Use scripts/import_bibtex.jl to import publications from BibTeX
Add images to _assets/images/
Customize styles in _css/custom.css

License
Content © Eric B. Ford. Site code under MIT License.
