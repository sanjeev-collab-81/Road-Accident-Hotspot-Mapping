# Road Accident Hotspot Analysis — Chennai Metropolitan Area

[![R](https://img.shields.io/badge/R-4.6.1-276DC3?logo=r)](https://www.r-project.org/)
[![rmarkdown](https://img.shields.io/badge/rmarkdown-HTML%20Report-blue)](https://rmarkdown.rstudio.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Project Summary

A complete end-to-end geospatial analysis of road accident data for the **Chennai Metropolitan Area (2023–2024)**. The project:

1. **Generates** ~3,000 synthetic accident records with realistic spatial clustering around known dangerous locations
2. **Detects hotspots** using DBSCAN (Density-Based Spatial Clustering) and ranks the top 5 danger zones
3. **Analyses patterns** by hour of day, weekday, weather condition, and road type
4. **Produces** a polished, self-contained interactive HTML report with Leaflet maps and ggplot2 charts

> **Note:** This project uses synthetic data designed to mirror realistic accident patterns around actual Chennai geography. In production, replace `data/accidents.csv` with real MORTH/police FIR data.

---

## Top 3 Findings

| # | Finding | Implication |
|---|---------|-------------|
| 1 | **70% of all accidents** cluster in just 5-6 geographic hotspots | Targeted infrastructure investment at these specific locations will have maximum safety impact |
| 2 | **Evening rush (5–7 PM)** is the most dangerous period — fatalities peak then | Time-based interventions (adaptive signals, increased patrols) should focus on this window |
| 3 | **Highways** have the highest *severity* despite lower accident counts — fog/rain multiplies risk | Speed enforcement cameras + fog-detection warning systems are highest-priority highway interventions |

---

## How to Run

### Prerequisites

Make sure you have R ≥ 4.0 and Pandoc ≥ 2.0 installed.

```r
# Install required packages (run once)
install.packages(c(
  "tidyverse", "lubridate", "sf", "leaflet", "leaflet.extras",
  "dbscan", "gt", "rmarkdown", "knitr", "scales", "gridExtra"
))
```

### Option A — Run Everything in One Step

```r
# From the project directory in R console:
setwd("path/to/road-accident-hotspot-analysis")
source("analysis.R")                                      # generates data + hotspots
rmarkdown::render("accident_report.Rmd",                  # knits the HTML report
                  output_file = "accident_report.html")
browseURL("accident_report.html")                         # opens in browser
```

### Option B — Run from PowerShell / Command Line

```powershell
# From project root:
Rscript analysis.R
Rscript -e "rmarkdown::render('accident_report.Rmd', output_file='accident_report.html')"
start accident_report.html
```

### Option C — RStudio

1. Open `accident_report.Rmd` in RStudio
2. Click the **Knit** button (or `Ctrl+Shift+K`)
3. The report renders in the Viewer pane and saves as `accident_report.html`

---

## Folder Structure

```
road-accident-hotspot-analysis/
│
├── data/
│   ├── accidents.csv          # Raw synthetic accident records (3,000 rows)
│   ├── accidents_clean.csv    # Cleaned dataset with derived time features
│   └── hotspots.csv           # Top 5 hotspot summary (centroid, counts, peak hour)
│
├── screenshots/
│   ├── hotspot_map.png        # Screenshot of the interactive hotspot map
│   └── accidents_by_hour.png  # Screenshot of the hour-of-day chart
│
├── analysis.R                 # Main analysis: data generation → DBSCAN → pattern summaries
├── accident_report.Rmd        # R Markdown source for the HTML report
├── accident_report.html       # Generated self-contained HTML report (after running)
├── README.md                  # This file
└── .gitignore                 # Git ignore rules
```

---

## Key R Packages Used

| Package | Purpose |
|---------|---------|
| `tidyverse` | Data manipulation (dplyr), visualisation (ggplot2), file I/O (readr) |
| `lubridate` | Date-time parsing and feature extraction |
| `sf` | Spatial features — converting coordinates to geometry objects |
| `dbscan` | Density-based spatial clustering for hotspot detection |
| `leaflet` + `leaflet.extras` | Interactive maps (cluster map, heatmap, hotspot circles) |
| `gt` | Publication-quality tables |
| `rmarkdown` + `knitr` | Literate programming — weaving code and narrative into HTML |
| `scales` | Formatting numbers and colour scales |
| `gridExtra` | Arranging multiple ggplot2 panels |

---

## Methodology Notes

### Synthetic Data Generation
- City centre: Chennai (lat 13.0827°N, lon 80.2707°E)
- `set.seed(123)` ensures reproducibility
- 70% of accidents placed in 5-6 tight clusters (σ ≈ 300 m) at real-ish dangerous locations
- Realistic time weighting: peak at 17:00–19:00; higher severity on highways and in bad weather

### DBSCAN Parameters
- `eps = 0.0045°` ≈ 500 m at Chennai's latitude — captures same-junction accidents
- `minPts = 15` — requires at least 15 accidents to form a meaningful cluster
- Points labelled `cluster_id = 0` are noise (scattered accidents not forming clusters)

### Severity Scoring
Hotspots are ranked by total accident count and characterised by a severity score:

```
severity_score = (Fatal×3 + Serious×2 + Minor×1) / total_accidents
```

A score of 3.0 = all fatal; 1.0 = all minor.

---

## Contributing

Issues and pull requests are welcome. To add real data:
1. Place your CSV in `data/accidents.csv` with the same column schema
2. Remove or skip the data-generation section in `analysis.R`
3. Re-run and re-knit

---

*Generated as part of Road Safety Analytics Initiative — Chennai Metropolitan Area*
