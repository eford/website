@def title = "Research"
@def mintoclevel = 1
@def maxtoclevel = 2
@def floattoc = true
--- 
{{insert head.html}}
{{insert nav.html}}
~~~
<main class="site-main">
<div class="franklin-content">
~~~

# Research Themes

My research group works on a range of topics in exoplanet science, from the development of novel observational and statistical methods to theoretical modeling of planetary system formation and dynamics. Below are someof our recent research areas.

\toc

---
## Extremely Precise Radial Velocity Surveys

Extremely precise radial velocity (EPRV) surveys are one of the most promising methods for detecting and characterizing Earth-like planets orbiting nearby Sun-like stars. Our group is actively involved in developing the observational strategies, data analysis pipelines, and statistical methods needed to push radial velocity precision to the level required to detect Earth analogs.

### Key Projects

**[NEID](https://neid.psu.edu/)** — A state-of-the-art radial velocity spectrograph on the WIYN 3.5m telescope at Kitt Peak National Observatory. Our group plays a leading role in the NEID science team.  We're also particulary active in using the NEID Solar Telescope, which observes the Sun-as-a-star to provide a unique dataset to develop and evaluate methods for characterizing and mitigating stellar variability.

**[Habitable Zone Planet Finder (HPF)](https://hpf.psu.edu/)** — A near-infrared spectrograph on the Hobby-Eberly Telescope designed to detect low-mass planets orbiting M dwarf stars in their habitable zones.

**Mitigating Stellar Variability** — A major challenge for EPRV surveys is distinguishing true planetary signals from apparent Doppler shifts caused by stellar surface phenomena. Our group develops data-driven and physics-informed approaches to simulating and mitigating the effects of stellar variability.

### Selected Publications
- Ford, E.B. et al. (2024). "Earths within Reach: Evaluation of Strategies for Mitigating Solar Variability using 3.5 years of NEID Sun-as-a-Star Observations." ArXiv:2408.13318
- Palumbo, M.L., Ford, E.B. et al. (2024). AJ, 168, 46. "GRASS II: Simulations of Potential Granulation Noise Mitigation Methods"
- Gilbertson, C., Ford, E.B. et al. (2024). "Data-Driven Modeling of Telluric Features and Stellar Variability with StellarSpectraObservationFitting.jl." ArXiv:2408.17289

---

## Exoplanet Demographics

Understanding the frequency, sizes, orbits, and architectures of planetary systems is essential for constraining theories of planet formation and evolution. Our group has developed statistical frameworks for measuring planet occurrence rates and characterizing the architectures of multi-planet systems using data from NASA's *Kepler* mission and other surveys.

### Key Contributions

**Occurrence Rates** — Bayesian and Approximate Bayesian Computation (ABC) methods to rigorously account for survey completeness, detection efficiency, and measurement uncertainties:
- Hsu, D.C., Ford, E.B. et al. (2019). AJ, 158, 3. "Occurrence Rates of Planets orbiting FGK Stars"
- Hsu, D.C., Ford, E.B., Terrien, R. (2020). MNRAS 498, 2249. "Occurrence Rates of Planets Orbiting M Stars"

**Planetary System Architectures (SysSim)** — Forward modeling framework characterizing distributions of multiplicities, sizes, periods, eccentricities, and mutual inclinations:
- He, M.Y., Ford, E.B., Ragozzine, D. (2019–2021). "Architectures of Exoplanetary Systems" series (MNRAS & AJ)

**Mass-Radius Relationships:**
- Wolfgang, A., Rogers, L.A., Ford, E.B. (2016). ApJ 825, 19. "Probabilistic Mass-Radius Relationship for Sub-Neptune-sized Planets"

---

## Radial Velocity Surveys
Our research group performs Bayesian analyses of Doppler observations of extrasolar planetary systems, particularly those with multiple planets.
We are working in close collaboration with both statisticians and observers, including the NEID, HPF and EXPRES teams.

---

## Transit Surveys
As a member of the science team for NASA’s Kepler mission, Ford and his research group contributed to the discovery and characterization of many interesting exoplanets. Now, most known exoplanets orbit stars with additional known planets. This presents new opportunities for using the relationships of planets in a system to understand the history of planet formation in these planetary systems.  In many cases, transit timing variations (TTVs) allow us to characterize the masses and orbits of exoplants in closely spaced and/or strongly interacting planetary sytems.
Our research group has focused on the characterization of exoplanet populations, combining rigorous statistical methods with a detailed understanding of the astronomical selection effects. 

---

## Orbital Dynamics & Planet Formation

The orbital architectures of observed planetary systems encode information about their formation and dynamical history. Our group uses N-body simulations, analytic theory, and statistical comparisons with observations to understand the processes that shape planetary systems.

### Key Topics

**Planet-Planet Scattering:**
- Rasio, F.A. & Ford, E.B. (1996). Science, 274, 954. "Dynamical Instabilities and the Formation of Extrasolar Planetary Systems"
- Chatterjee, S., Ford, E.B. et al. (2008). ApJ, 686, 580. "Dynamical Outcomes of Planet-Planet Scattering"
- Ford, E.B. & Rasio, F.A. (2008). ApJ, 686, 621. "Origins of Eccentric Extrasolar Planets"

**Formation of Short-Period Planets:**
- Carrera, D., Ford, E.B., Izidoro, A. (2019). MNRAS 486, 3874
- Zawadzki, B., Carrera, D., Ford, E.B. (2021). MNRAS 503, 1390
- Zawadzki, B., Carrera, D., Ford, E.B. (2022). ApJ, 937, 53. "Migration traps as the root cause of the Kepler dichotomy"

---

## Astrostatistics & Data Science Methods

Extracting reliable scientific conclusions from astronomical observations requires sophisticated statistical methods. Our group develops and applies Bayesian inference, MCMC algorithms, Gaussian processes, and approximate Bayesian computation.

### Key Contributions

**Review Articles:**
- Hara, N. & Ford, E.B. (2023). Annual Review of Statistics and Its Application, v10, 623–649. "Statistical methods for exoplanet detection with radial velocities"
- Ford, E.B. (2014). PNAS, 111, 12616. "Architectures of Planetary Systems and Implications for their Formation"

**MCMC Methods for Exoplanets:**
- Ford, E.B. (2005). AJ, 129, 1706. "Quantifying the uncertainty in the orbits of extrasolar planets"
- Ford, E.B. (2006). ApJ, 642, 505. "Improving the efficiency of Markov chain Monte Carlo"
- Nelson, B., E.B. Ford & M.J. Payne (2014) ApJS 210, 11. "RUN DMC: An Efficient, Parallel Code for Analyzing Radial Velocity Observations Using N-body Integrations and Differential Evolution Markov Chain Monte Carlo"
- Nelson et al. (2020) AJ 159, 73. "Quantifying the Bayesian Evidence for a Planet in Radial Velocity Data"
---

## High-Performance Computing for Astrophysics

Many problems in astrophysics require significant computational resources. Our group develops high-performance computing tools and techniques, with emphasis on the [Julia programming language](https://julialang.org/), GPU computing, and parallel algorithms.

You can find several open-source codes from group members on GitHub:
- Exoplanet Demographics
   - [ExoPlanets SysSim](https://github.com/ExoJulia/ExoplanetsSysSim.jl)
   - [SysSimExClustesr](https://github.com/ExoJulia/SysSimExClusters)
   - [SysSimPyMMEN](https://github.com/hematthi/SysSimPyMMEN)
- Extremely Precise Radial Velocities
   - [GPLinearODEMaker.jl](https://github.com/christiangil/GPLinearODEMaker.jl)
   - [GRASS](https://github.com/palumbom/GRASS)
   - [StellarSpectraObservationFitting.jl](https://github.com/RvSpectML/StellarSpectraObservationFitting.jl)
   - [SSOFApplication](https://github.com/christiangil/SSOFApplication)
- Utilities
   - [ExpectationMaximizationPCA.jl](https://github.com/christiangil/ExpectationMaximizationPCA.jl)
   - [PlutoTeachingTools.jl](https://github.com/JuliaPluto/PlutoTeachingTools.jl)
---

## Astrobiology

Searching for evidence of life on other planets will require a combination of power observatories, advanced instrumentation, creative approaches, and state-of-the-art statistical methods.  



---
# Additional Information
You can find additional information about:
- [Team Members](/group)
- [External Resources](links)
- [Support for our Research Group](support)


~~~
</div>
</main>
~~~
