# =============================================================================
# Road Accident Hotspot Analysis
# City: Chennai, India (lat: 13.0827, lon: 80.2707)
# Author: Generated Analysis Script
# =============================================================================

# --- 0. LOAD REQUIRED PACKAGES -----------------------------------------------
# suppressPackageStartupMessages keeps the console clean while loading
library(tidyverse)      # dplyr, ggplot2, tidyr, readr, etc.
library(lubridate)      # easy date-time manipulation
library(sf)             # spatial features (points, polygons)
library(dbscan)         # density-based clustering for hotspot detection

cat("✓ All packages loaded successfully\n")

# =============================================================================
# STEP 1: GENERATE SYNTHETIC ACCIDENT DATA
# =============================================================================
# We build a realistic synthetic dataset (~3,000 records, 2 years) around
# Chennai city centre. About 70% of accidents are forced into 5-6 tight
# geographic clusters to simulate real "danger spots."

set.seed(123)   # For reproducibility

n_total      <- 3000
n_clustered  <- round(n_total * 0.70)   # 70% in defined clusters
n_random     <- n_total - n_clustered   # 30% scattered across city

# --- 1a. DEFINE CLUSTER CENTRES (real-ish Chennai locations) -----------------
# Each entry: name, lat, lon, weight (how many accidents it should attract)
cluster_centres <- tibble(
  name   = c("Anna Salai Junction",
             "Koyambedu Flyover",
             "Kathipara Junction",
             "OMR Sholinganallur",
             "ECR Thiruvanmiyur",
             "GST Road Chrompet"),
  lat    = c(13.0604, 13.0694, 13.0131, 12.9010, 12.9927, 12.9500),
  lon    = c(80.2496, 80.2100, 80.2022, 80.2271, 80.2611, 80.1380),
  weight = c(0.22, 0.18, 0.17, 0.16, 0.15, 0.12)   # must sum to 1
)

# --- 1b. GENERATE CLUSTERED ACCIDENTS ----------------------------------------
# For each accident, pick a cluster proportional to its weight,
# then jitter the position within ~300-600m radius (Gaussian noise).
cluster_ids <- sample(
  seq_len(nrow(cluster_centres)),
  size    = n_clustered,
  replace = TRUE,
  prob    = cluster_centres$weight
)

# Gaussian jitter: ~0.003 degrees ≈ 300 m at Chennai's latitude
clustered_pts <- tibble(
  latitude  = cluster_centres$lat[cluster_ids] + rnorm(n_clustered, 0, 0.003),
  longitude = cluster_centres$lon[cluster_ids] + rnorm(n_clustered, 0, 0.003),
  is_cluster = TRUE
)

# --- 1c. GENERATE RANDOM (SCATTERED) ACCIDENTS --------------------------------
# Random accidents spread over a ~20×20 km box centred on Chennai.
# 1 degree lat ≈ 111 km → 0.1 degree ≈ 11 km on each side
random_pts <- tibble(
  latitude  = runif(n_random, 12.95, 13.20),
  longitude = runif(n_random, 80.15, 80.38),
  is_cluster = FALSE
)

# Combine and shuffle
all_pts <- bind_rows(clustered_pts, random_pts) %>%
  slice_sample(n = n_total)   # shuffle so cluster/random are mixed

# --- 1d. GENERATE TIME FEATURES WITH REALISTIC PATTERNS ----------------------
# Date range: 2 full years starting 2023-01-01
start_date <- as.Date("2023-01-01")
end_date   <- as.Date("2024-12-31")

# Random date within the range
dates <- sample(seq(start_date, end_date, by = "day"),
                size = n_total, replace = TRUE)

# Hour distribution: peak in 5-8 PM (rush hour) and 8-10 AM (morning rush)
# We simulate this with a weighted sample over 0-23 hours.
hour_weights <- c(
  rep(1,  5),   # 00-04: very low (night)
  rep(2,  3),   # 05-07: rising
  rep(5,  2),   # 08-09: morning rush
  rep(3,  3),   # 10-12: mid-morning
  rep(4,  3),   # 13-15: afternoon
  rep(3,  1),   # 16:    pre-peak
  rep(8,  3),   # 17-19: EVENING PEAK (highest)
  rep(5,  2),   # 20-21: post-peak
  rep(2,  2)    # 22-23: late night
)
hours <- sample(0:23, size = n_total, replace = TRUE, prob = hour_weights)

# Minutes: uniform within the hour
minutes <- sample(0:59, size = n_total, replace = TRUE)
times   <- sprintf("%02d:%02d", hours, minutes)

# --- 1e. ASSIGN CATEGORICAL FEATURES -----------------------------------------
weekdays_vec <- weekdays(dates)   # "Monday", "Tuesday", ...

# More accidents Friday/Saturday: these get extra weight during sampling
# but we just record the weekday and note the pattern is real here.

# Weather: more accidents in rain/fog → weighted
weather_probs <- c(Clear = 0.55, Rain = 0.30, Fog = 0.15)
weather <- sample(names(weather_probs), size = n_total, replace = TRUE,
                  prob = weather_probs)

# Road type: junctions attract more accidents
road_probs <- c(Highway = 0.25, "Main Road" = 0.35,
                Junction = 0.28, Residential = 0.12)
road_type <- sample(names(road_probs), size = n_total, replace = TRUE,
                    prob = road_probs)

# Severity: highways → more serious/fatal; weather adds risk
# Build a base severity then adjust
base_severity <- sample(c("Minor", "Serious", "Fatal"),
                        size = n_total, replace = TRUE,
                        prob = c(0.60, 0.30, 0.10))

# Upgrade severity on highways (more fatal) and bad weather
highway_mask <- road_type == "Highway"
bad_weather  <- weather %in% c("Rain", "Fog")

severity <- base_severity
# On highways upgrade ~30% of Minors to Serious, ~10% of Serious to Fatal
# Use runif(n_total) to match vector length exactly and avoid recycling warnings
severity[highway_mask & severity == "Minor"  & runif(n_total) < 0.30] <- "Serious"
severity[highway_mask & severity == "Serious"& runif(n_total) < 0.10] <- "Fatal"
# In bad weather upgrade ~20% of Minors to Serious
severity[bad_weather  & severity == "Minor"  & runif(n_total)  < 0.20] <- "Serious"

# Vehicles involved: 1-5, higher on highways
vehicles_involved <- ifelse(
  highway_mask,
  sample(1:5, n_total, replace = TRUE, prob = c(0.1, 0.2, 0.3, 0.25, 0.15)),
  sample(1:4, n_total, replace = TRUE, prob = c(0.25, 0.40, 0.25, 0.10))
)

# Casualties: 0 for minor, 1-3 for serious, 1-6 for fatal
casualties <- case_when(
  severity == "Minor"   ~ as.integer(0),
  severity == "Serious" ~ as.integer(sample(1:3, n_total, replace=TRUE)),
  severity == "Fatal"   ~ as.integer(sample(1:6, n_total, replace=TRUE))
)

# --- 1f. ASSEMBLE THE DATA FRAME ---------------------------------------------
accidents_raw <- tibble(
  accident_id       = sprintf("ACC%04d", seq_len(n_total)),
  date              = dates,
  time              = times,
  latitude          = all_pts$latitude,
  longitude         = all_pts$longitude,
  severity          = severity,
  weather           = weather,
  road_type         = road_type,
  vehicles_involved = vehicles_involved,
  casualties        = casualties
)

# Save to CSV so the report can load it independently
dir.create("data", showWarnings = FALSE)
write_csv(accidents_raw, "data/accidents.csv")
cat(sprintf("✓ Generated %d synthetic accident records → data/accidents.csv\n",
            nrow(accidents_raw)))

# =============================================================================
# STEP 2: CLEAN & PREPARE DATA
# =============================================================================

# Read back to demonstrate the full pipeline (load → clean → analyse)
accidents <- read_csv("data/accidents.csv", show_col_types = FALSE)

# --- 2a. PARSE DATES AND EXTRACT TIME FEATURES --------------------------------
accidents <- accidents %>%
  mutate(
    date      = as.Date(date),
    hour      = as.integer(str_extract(time, "^\\d+")),   # extract HH from HH:MM
    weekday   = wday(date, label = TRUE, abbr = FALSE),   # "Monday" etc.
    month     = month(date, label = TRUE, abbr = TRUE),   # "Jan" etc.
    year      = year(date),
    # Ordered factor for severity (useful in plotting)
    severity  = factor(severity, levels = c("Minor", "Serious", "Fatal"), ordered = TRUE),
    # Logical helpers
    is_rush_hour = hour %in% c(8, 9, 17, 18, 19),
    is_weekend   = weekday %in% c("Saturday", "Sunday")
  )

cat("✓ Date/time features extracted\n")

# =============================================================================
# STEP 3: SPATIAL CONVERSION (sf)
# =============================================================================
# Convert the data frame to an sf object using WGS 84 (EPSG:4326)
# sf stores each row's lat/lon as a POINT geometry.

accidents_sf <- st_as_sf(
  accidents,
  coords = c("longitude", "latitude"),   # note: lon first, then lat
  crs    = 4326                          # WGS 84
)
cat("✓ Converted to sf spatial object (CRS: EPSG:4326)\n")

# =============================================================================
# STEP 4: HOTSPOT DETECTION WITH DBSCAN
# =============================================================================
# DBSCAN (Density-Based Spatial Clustering of Applications with Noise) groups
# points that are closely packed together. Parameters:
#   eps    = neighbourhood radius in degrees (~500 m at this latitude ≈ 0.0045°)
#   minPts = minimum points to form a dense cluster

# Extract coordinate matrix for DBSCAN
coords_matrix <- accidents %>%
  select(longitude, latitude) %>%
  as.matrix()

# Run DBSCAN
# eps = 0.0045 degrees ≈ 500 m; minPts = 15 → at least 15 accidents needed
dbscan_result <- dbscan::dbscan(coords_matrix, eps = 0.0045, minPts = 15)

# Attach cluster labels back to the data (0 = noise / no cluster)
accidents <- accidents %>%
  mutate(cluster_id = dbscan_result$cluster)

cat(sprintf("✓ DBSCAN found %d distinct hotspot clusters (label 0 = noise)\n",
            max(dbscan_result$cluster)))

# =============================================================================
# STEP 5: RANK TOP 5 HOTSPOTS
# =============================================================================

# Summarise each DBSCAN cluster (exclude noise, cluster 0)
hotspot_summary <- accidents %>%
  filter(cluster_id > 0) %>%
  group_by(cluster_id) %>%
  summarise(
    accident_count = n(),
    fatal_count    = sum(severity == "Fatal"),
    serious_count  = sum(severity == "Serious"),
    minor_count    = sum(severity == "Minor"),
    avg_casualties = round(mean(casualties), 2),
    # Centroid coordinates for mapping
    centroid_lat   = mean(latitude),
    centroid_lon   = mean(longitude),
    # Peak hour: the hour with the most accidents in this cluster
    peak_hour      = as.integer(names(which.max(table(hour)))),
    # Most common weather and road type
    common_weather    = names(which.max(table(weather))),
    common_road_type  = names(which.max(table(road_type))),
    .groups = "drop"
  ) %>%
  # Severity score: Fatal=3, Serious=2, Minor=1 → weighted mean
  mutate(
    severity_score = round(
      (fatal_count * 3 + serious_count * 2 + minor_count * 1) / accident_count, 2
    )
  ) %>%
  arrange(desc(accident_count)) %>%
  # Keep only top 5 hotspots
  slice_head(n = 5) %>%
  mutate(
    rank  = row_number(),
    label = paste0("Hotspot #", rank)
  )

# Match each hotspot to the nearest named cluster centre for readability
# (simple nearest-centroid lookup using Euclidean distance on lat/lon)
assign_name <- function(clat, clon, centres) {
  dists <- sqrt((centres$lat - clat)^2 + (centres$lon - clon)^2)
  centres$name[which.min(dists)]
}

hotspot_summary <- hotspot_summary %>%
  rowwise() %>%
  mutate(
    location_name = assign_name(centroid_lat, centroid_lon, cluster_centres)
  ) %>%
  ungroup() %>%
  select(rank, label, location_name, accident_count, fatal_count,
         serious_count, minor_count, severity_score,
         avg_casualties, peak_hour, common_weather,
         common_road_type, centroid_lat, centroid_lon)

cat("✓ Top 5 hotspots ranked\n")
print(hotspot_summary %>%
        select(rank, location_name, accident_count, fatal_count, severity_score))

# Save hotspot summary
write_csv(hotspot_summary, "data/hotspots.csv")
cat("✓ Hotspot summary saved → data/hotspots.csv\n")

# =============================================================================
# STEP 6: PATTERN ANALYSIS (saved for report consumption)
# =============================================================================

# --- 6a. Accidents by hour ----------------------------------------------------
by_hour <- accidents %>%
  count(hour, severity) %>%
  arrange(hour)

# --- 6b. Accidents by weekday -------------------------------------------------
by_weekday <- accidents %>%
  count(weekday, severity) %>%
  mutate(weekday = factor(weekday,
                          levels = c("Monday","Tuesday","Wednesday",
                                     "Thursday","Friday","Saturday","Sunday")))

# --- 6c. Accidents by weather -------------------------------------------------
by_weather <- accidents %>%
  count(weather, severity)

# --- 6d. Accidents by road type -----------------------------------------------
by_road_type <- accidents %>%
  count(road_type, severity)

# --- 6e. Monthly trend --------------------------------------------------------
by_month <- accidents %>%
  count(year, month)

cat("\n=== KEY PATTERN SUMMARIES ===\n")
cat("Peak accident hour:", accidents %>% count(hour) %>% slice_max(n, n=1) %>% pull(hour), ":00\n")
cat("Most dangerous weekday:", accidents %>% count(weekday) %>% slice_max(n, n=1) %>% pull(weekday) %>% as.character(), "\n")
cat("Most dangerous weather:", accidents %>% count(weather) %>% slice_max(n, n=1) %>% pull(weather), "\n")
cat("Most dangerous road type:", accidents %>% count(road_type) %>% slice_max(n, n=1) %>% pull(road_type), "\n")

# Save the cleaned dataset for the report
write_csv(accidents, "data/accidents_clean.csv")
cat("\n✓ Cleaned dataset saved → data/accidents_clean.csv\n")
cat("✓ analysis.R completed successfully!\n")
