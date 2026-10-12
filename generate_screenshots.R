library(tidyverse)
library(lubridate)
library(sf)
library(leaflet)
library(leaflet.extras)
library(dbscan)
library(scales)
library(webshot2)
library(htmlwidgets)

# Load data
accidents <- read_csv("data/accidents_clean.csv", show_col_types = FALSE) %>%
  mutate(
    severity = factor(severity, levels = c("Minor", "Serious", "Fatal"), ordered = TRUE),
    hour     = as.integer(hour)
  )
hotspots <- read_csv("data/hotspots.csv", show_col_types = FALSE)

dir.create("screenshots", showWarnings = FALSE)

# ── SCREENSHOT 1: Hotspot Map ────────────────────────────────────────────────
cat("Generating hotspot map screenshot...\n")

clr_minor <- "#3498db"; clr_serious <- "#f39c12"; clr_fatal <- "#e74c3c"
pal_hs <- colorNumeric(
  palette = c("#3498db", "#f39c12", "#e74c3c"),
  domain  = c(1, 3)
)
max_acc <- max(hotspots$accident_count)

hotspots <- hotspots %>%
  mutate(popup_hs = paste0(
    "<div style='font-family:sans-serif;min-width:180px;'>",
    "<h4 style='margin:0 0 6px;color:#c0392b;'>", label, "</h4>",
    "<b>", location_name, "</b><br>",
    "Total: <b>", accident_count, "</b> | Fatal: <b>", fatal_count, "</b>",
    "</div>"
  ))

hotspot_map <- leaflet() %>%
  addProviderTiles(providers$CartoDB.Positron) %>%
  addCircleMarkers(
    data = accidents, lng = ~longitude, lat = ~latitude,
    radius = 2, color = "grey", fillOpacity = 0.12, stroke = FALSE
  ) %>%
  addCircleMarkers(
    data = hotspots, lng = ~centroid_lon, lat = ~centroid_lat,
    radius = ~scales::rescale(accident_count, to=c(20,55), from=c(0,max_acc)),
    color = ~pal_hs(severity_score), fillColor = ~pal_hs(severity_score),
    fillOpacity = 0.55, weight = 3, opacity = 0.9,
    popup = ~popup_hs, label = ~label
  ) %>%
  addLabelOnlyMarkers(
    data = hotspots, lng = ~centroid_lon, lat = ~centroid_lat,
    label = ~paste0(label, ": ", location_name),
    labelOptions = labelOptions(
      noHide = TRUE, direction = "top", offset = c(0, -30),
      style = list("font-weight"="bold","font-size"="11px",
                   "background-color"="rgba(255,255,255,0.9)","border"="1px solid #ccc",
                   "border-radius"="4px","padding"="2px 6px")
    )
  ) %>%
  addLegend(position="bottomright", pal=pal_hs, values=hotspots$severity_score,
            title="Severity Score") %>%
  setView(lng=80.22, lat=13.01, zoom=11)

# Save as HTML then screenshot
tmp_html <- tempfile(fileext = ".html")
saveWidget(hotspot_map, tmp_html, selfcontained = TRUE)
webshot2::webshot(tmp_html, "screenshots/hotspot_map.png",
                  vwidth = 1400, vheight = 800, delay = 4, zoom = 1.5)
cat("✓ Hotspot map screenshot saved\n")

# ── SCREENSHOT 2: Accidents by Hour Chart ────────────────────────────────────
cat("Generating hour chart screenshot...\n")

by_hour_df <- accidents %>%
  count(hour, severity) %>%
  mutate(severity = factor(severity, levels = c("Minor","Serious","Fatal")))

sev_colours <- c(Minor="#3498db", Serious="#f39c12", Fatal="#e74c3c")

p_hour <- ggplot(by_hour_df, aes(x=hour, y=n, fill=severity)) +
  geom_col(width=0.8, position="stack", alpha=0.92) +
  scale_fill_manual(values=sev_colours, name="Severity") +
  scale_x_continuous(breaks=0:23, labels=paste0(0:23,"h")) +
  scale_y_continuous(expand=c(0,0)) +
  annotate("rect", xmin=16.5, xmax=19.5, ymin=0, ymax=Inf, alpha=0.1, fill="#e74c3c") +
  annotate("text", x=18, y=max(by_hour_df %>% group_by(hour) %>% summarise(t=sum(n)) %>% pull(t))*0.93,
           label="Evening\nRush", color="#c0392b", size=4, fontface="bold") +
  labs(
    title = "Road Accidents by Hour of Day — Chennai 2023–2024",
    subtitle = "Evening rush hour (17:00–19:00) highlighted — stacked by severity",
    x = "Hour of Day", y = "Number of Accidents"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face="bold", size=18, color="#2c3e50"),
    plot.subtitle = element_text(color="#7f8c8d", size=13),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    axis.text.x = element_text(angle=45, hjust=1, size=9),
    legend.position = "top",
    plot.background = element_rect(fill="white", color=NA),
    panel.background = element_rect(fill="white", color=NA)
  )

ggsave("screenshots/accidents_by_hour.png", p_hour,
       width=14, height=7, dpi=150, bg="white")
cat("✓ Hour chart screenshot saved\n")

cat("\n✓ All screenshots generated in screenshots/\n")
