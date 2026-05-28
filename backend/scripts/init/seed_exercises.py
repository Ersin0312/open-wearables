#!/usr/bin/env python3
"""Seed the exercise library with the complete Gym80 catalog (Weight Stack + Plate Loaded).

Data sourced from gym80.de. Images are expected to be locally hosted in
`frontend/public/images/exercises/<model_no>.webp` (see scripts/init/download_gym80_images.sh).

Idempotent: skips entries whose `name` already exists. Run via:
    docker compose exec app uv run python scripts/init/seed_exercises.py
"""

from uuid import uuid4

from app.database import SessionLocal
from app.models import Exercise


# Schema: (model_no_lower, display_name, primary_muscle_group, default_split_tag, source_image_url)
# image_url in DB will become "/images/exercises/<model_no_lower>.webp" (local hosted)
GYM80_CATALOG: list[dict[str, str]] = [
    # ===== WEIGHT STACK =====
    # Page 1
    {"model": "3001", "name": "3001 Beinstrecker", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/03/3001_beinbeuger_NC-1.webp"},
    {"model": "3002", "name": "3002 Beinbeuger Liegend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/11/3002_lying_leg_curl_NC-1024x640.webp"},
    {"model": "3003", "name": "3003 Beinbeuger Sitzend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/03/3003_beinbeuger_sitzend_NC.webp"},
    {"model": "3004", "name": "3004 Gluteus Kick Kniend", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3004_gluteus_kick_Kniend_NC-1024x640.webp"},
    {"model": "3005", "name": "3005 Gluteus Kick Radial", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3005_gluteus_kick_radial_NC-1024x640.webp"},
    {"model": "3006", "name": "3006 Kickmaschine", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3006_kickmaschine_NC-1024x640.webp"},
    {"model": "3007", "name": "3007 Rückenstrecker", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3007_rueckenstrecker_NC-1024x640.webp"},
    {"model": "3008", "name": "3008 Klappsitz (Crunch)", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/3008_klappsitz_NC-1024x640.webp"},
    {"model": "3010", "name": "3010 Bizepsmaschine", "muscle": "biceps", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3010_bizepsmaschine_NC-1024x640.webp"},
    {"model": "3011", "name": "3011 Trizepsmaschine", "muscle": "triceps", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3011_trizepsmaschine_NC-1024x640.webp"},
    {"model": "3012n", "name": "3012N Überzugmaschine (Pullover)", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3012n_ueberzugmaschine_NC-1024x640.webp"},
    {"model": "3013", "name": "3013 Beinbeuger Stehend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3013_beinbeuger_stehend_NC-1024x640.webp"},
    {"model": "3014", "name": "3014 Brustmaschine", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3014_brustmaschine_NC-1024x640.webp"},
    {"model": "3016", "name": "3016 Brustpresse", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3016_brustpresse_NC-1024x640.webp"},
    {"model": "3017", "name": "3017 Klimmzug-Barrenmaschine", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3017_klimmzug-barrenmaschine_NC-1024x640.webp"},
    {"model": "3018", "name": "3018 Wadenmaschine Stehend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3018_wandenmaschine_stehend_NC-1024x640.webp"},
    {"model": "3020", "name": "3020 Rückenzugmaschine (Lat Pulldown)", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3020_rueckenzugmaschine_NC-1024x640.webp"},
    {"model": "3021", "name": "3021 Butterfly mit Pads", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3021_butterfly_mit_pads_NC-1024x640.webp"},
    {"model": "3022", "name": "3022 Butterfly", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3022_butterfly_NC-1024x640.webp"},
    {"model": "3023n", "name": "3023N Schrägbank", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3023n_schraegbank_NC-1024x640.webp"},
    # Page 2
    {"model": "3025", "name": "3025 Butterfly Reverse (Rear Delts)", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3025_butterfly_reverse_NC-1024x640.webp"},
    {"model": "3027", "name": "3027 Wadenpresse Sitzend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3027_wandenpresse_sitzend_NC-1024x640.webp"},
    {"model": "3028", "name": "3028 Abduktionsmaschine", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3028_abduktionsmaschine_NC-1024x640.webp"},
    {"model": "3029", "name": "3029 Adduktionsmaschine", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3029_addunktionsmaschine_NC-1024x640.webp"},
    {"model": "3030", "name": "3030 Beinpresse Sitzend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3030_beinpresse_sitend_NC-1024x640.webp"},
    {"model": "3031", "name": "3031 Beinpresse Liegend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3031_beinpresse_liegend_NC-1024x640.webp"},
    {"model": "3032", "name": "3032 Schulterpresse", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3032_schulterpresse_NC-1024x640.webp"},
    {"model": "3034", "name": "3034 Klappsitz Liegend", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/3034_klappsitz_liegend_NC-1024x640.webp"},
    {"model": "3036", "name": "3036 Dipmaschine", "muscle": "triceps", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3036_dipmaschine_NC-1024x640.webp"},
    {"model": "3037", "name": "3037 Bauchmuskelmaschine", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/3037_bauchmuskelmaschine_NC-1024x640.webp"},
    {"model": "3038", "name": "3038 Rückenstrecker (Variante)", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3038_rueckensterecker_NC-1024x640.webp"},
    {"model": "3039", "name": "3039 Rudermaschine ohne Brustpolster", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3039_rudermaschine_ohne_brustpolster_NC-1024x640.webp"},
    {"model": "3040", "name": "3040 Rudermaschine", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3040_rudermaschine_NC-1024x640.webp"},
    {"model": "3041", "name": "3041 Brustpresse Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3041_brustpresse_dual_NC-1024x640.webp"},
    {"model": "3042", "name": "3042 Schrägbank Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3042_schraegbank_dual_NC-1024x640.webp"},
    {"model": "3043", "name": "3043 Schulterpresse Dual", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3043_schultepresse_dual_NC-1024x640.webp"},
    {"model": "3044", "name": "3044 Rückenzugmaschine Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3044_rueckenzugmaschine_dual_NC-1024x640.webp"},
    {"model": "3045", "name": "3045 Rudermaschine Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3045_rundermaschine_dual_NC-1024x640.webp"},
    {"model": "3046", "name": "3046 Beinpresse Dual", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/3046_beinpresse_dual_NC-1024x640.webp"},
    {"model": "3047", "name": "3047 ISO Lat", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3047_iso_lat_NC-1024x640.webp"},
    # Page 3
    {"model": "3050", "name": "3050 Seithebemaschine", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3050_seithebemaschine_NC-1024x640.webp"},
    {"model": "3069", "name": "3069 Stehende Abduktion", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/03/1773224158951-81n3lmfuu.webp"},
    {"model": "3071", "name": "3071 Unterarmmaschine", "muscle": "biceps", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3071_unterarmmaschin_NC-1024x640.webp"},
    {"model": "3094", "name": "3094 Donkey Calf Raise", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/03/1773224223746-tx1zkkh7i7r.webp"},
    {"model": "3095", "name": "3095 Trizeps Überkopf", "muscle": "triceps", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3095_trizeps_ueberkopf_NC-1024x640.webp"},
    {"model": "3096", "name": "3096 Nackendrückmaschine", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3096_neckpress_NC-1024x640.webp"},
    {"model": "3097", "name": "3097 Inner Chest Press", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/3097_inner_chest_press_NC-1024x640.webp"},
    {"model": "3098", "name": "3098 Bizeps Horizontal", "muscle": "biceps", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/3098_bizeps_horizontal_NC-1024x640.webp"},
    {"model": "3099", "name": "3099 Seithebemaschine Stehend", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/11/3099_standing_shoulder_lateral_raise_NC-1024x640.webp"},
    {"model": "3121", "name": "3121 Brustmaschine Stehend", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/11/3121_standing_chest_crossover_machine_NC-1024x640.webp"},
    {"model": "3123", "name": "3123 Beinstrecker Liegend (verstellbar)", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/04/gym80_3123_leg_extension_with_adjustable_backrest_NC_overview.webp"},
    {"model": "3124", "name": "3124 Crunchmaschine", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2026/04/3124_Crunchmaschine_NC_overview.webp"},
    {"model": "3225", "name": "3225 Rotationsmaschine", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/3225_rotationsrmaschine_NC-1024x640.webp"},
    {"model": "4004", "name": "4004 Kabelzug Crossover", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4004_kabelzug_crossover_NC-1024x640.webp"},
    {"model": "4012", "name": "4012 Kabelzug Crossover Verstellbar", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4012_kabelzug_crossover_verstellbar_NC-1024x640.webp"},
    {"model": "4016", "name": "4016 Ruderstation", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4016_ruderstation_NC-1024x640.webp"},
    {"model": "4032", "name": "4032 4-Stationenturm", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4032_bandzug_stationenturm_NC-1024x640.webp"},
    {"model": "4033", "name": "4033 Duplexstation", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4033_duplexstation_NC-1024x640.webp"},
    {"model": "4034", "name": "4034 Dual Verstellbarer Seilzug", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4034_dual_verstellbarer_seilzug_NC-1024x640.webp"},
    {"model": "4036", "name": "4036 Multidrückstation", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4036_multidrueckstation_NC-1024x640.webp"},
    # Page 4
    {"model": "4042", "name": "4042 Seilzug V-Station", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4042_seilzug_v-station_NC-1024x640.webp"},
    {"model": "4044", "name": "4044 5-Stationenturm", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4044_5-stationenturm_NC-1024x640.webp"},
    {"model": "4116", "name": "4116 Rückenzugstation", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4116_rueckenzugstation_NC-1024x640.webp"},
    {"model": "4117", "name": "4117 5-Stationenturm (Variante)", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4117_5-stationenturm_NC-1024x640.webp"},
    {"model": "4125", "name": "4125 Seilzug Explosiv", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4125_seitzug_explosiv_NC-1024x640.webp"},
    {"model": "4134", "name": "4134 Seilzug Universal", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4134_universal_seilzug_NC-1024x640.webp"},
    {"model": "4170", "name": "4170 8-Stationenturm", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4170_8-stationenturm_NC-1024x640.webp"},
    {"model": "4401", "name": "4401 FTM Deadlift Maschine", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4401_ftm_deadlift_maschine_NC-1024x640.webp"},
    {"model": "4402", "name": "4402 FTM Schulter und Brustpresse", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4402_ftm_schulter_und_brustpresse_NC-1024x640.webp"},
    {"model": "4403", "name": "4403 FTM Zug und Drückmaschine", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4403_ftm_zug_und_druckmaschine_NC-1024x640.webp"},
    {"model": "4416", "name": "4416 Bootymizer", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4416_bootymizer_NC-1024x640.webp"},
    {"model": "4900", "name": "4900 Incline Row Combo", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4900_incline_row_combo_NC-1024x640.webp"},
    {"model": "5001", "name": "5001 Innovation Beinpresse", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/5001_innovation_beinpresse_NC-1024x640.webp"},
    {"model": "5002", "name": "5002 Innovation Gluteusmaschine", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/5002_innovation_gluteusmascine_NC-1024x640.webp"},
    {"model": "5003", "name": "5003 Innovation Rudermaschine", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/5003_innovation_rudermaschine_NC-1024x640.webp"},
    {"model": "5004", "name": "5004 Innovation Curler Maschine", "muscle": "biceps", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/5004_innovation_curler_maschine_NC-1024x640.webp"},
    {"model": "5006", "name": "5006 Innovation Multistreckmaschine", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/5006_innovation_multistreckmaschine_NC-1024x640.webp"},
    {"model": "5011", "name": "5011 Abduktion und Adduktion Combo", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/11/5011_abduction_and_adduction_combo_NC-1024x640.webp"},
    {"model": "5012", "name": "5012 Bauch und Rücken Combo", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/5012_bauch_und_ruecken_combo_NC-1024x640.webp"},
    {"model": "5013", "name": "5013 Beinbeuger und Beinstrecker Combo", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/5013_beinbeuger_beinstrecker_combo_NC-1024x640.webp"},
    # Page 5
    {"model": "5014", "name": "5014 Butterfly und Butterfly Reverse Combo", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/5014_butterfly_butterfly_reverse_combo_NC-1024x640.webp"},
    {"model": "5015", "name": "5015 Schulter und Latzug Combo", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/5015_schulter_und_latzug_combo_NC-1024x640.webp"},
    {"model": "5101", "name": "5101 Cable Art Nr. 1 - Schulter & Rücken+", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/5101_cable_art_nr1-schulterruecken_NC-1024x640.webp"},
    {"model": "5102", "name": "5102 Cable Art Nr. 2 - Latissimus & Trapezius+", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/5102_cable_art_nr2-latissimus_und_trapezius_NC-1024x640.webp"},
    {"model": "5103", "name": "5103 Cable Art Nr. 3 - Brust & Schulter+", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/5103_cable_art_nr3-brust_und_schulter_NC-1024x640.webp"},
    {"model": "5104", "name": "5104 Cable Art Nr. 4 - Bizeps & Trizeps+", "muscle": "biceps", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/11/5104_cable_art_nr4-bizeps-triyeps_NC-1024x640.webp"},
    {"model": "5105", "name": "5105 Cable Art Nr. 5 - Oberkörper", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/5105_cable_art_nr5-oberkourper_NC-1024x640.webp"},
    {"model": "5106", "name": "5106 Cable Art Nr. 6 - Beine", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/5106_cable_art_nr6-beine_NC-1024x640.webp"},
    {"model": "5201", "name": "5201 Multi-Power Station", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/5201_multi_power_station_NC-1024x640.webp"},
    {"model": "5242", "name": "5242 Multi-Power Station PrivateGym", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/5242_multi-power_station_privategym_NC-1024x640.webp"},

    # ===== PLATE LOADED (Pure Kraft) =====
    {"model": "4018", "name": "4018 Pure Kraft Rudermaschine T-Bar", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4018_pure_kraf_rundermaschine_t-bar_NC-1024x640.webp"},
    {"model": "4023", "name": "4023 Pure Kraft 45 Grad Beinpresse", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4023_pure_kraft_45_grad_beinpresse_NC-1024x640.webp"},
    {"model": "4026", "name": "4026 Pure Kraft Wadenmaschine Sitzend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4026_pure_kraft_wadnenmaschine_sitzend_NC-1024x640.webp"},
    {"model": "4038", "name": "4038 Pure Kraft Kniebeugemaschine", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4038_pure_kraft_Kniebeugemaschine_NC-1024x640.webp"},
    {"model": "4038n", "name": "4038N Pure Kraft Kniebeugemaschine (NEW)", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/04/Comig-soonv2-4038N.webp"},
    {"model": "4159n", "name": "4159N Pure Kraft Hackenschmidt", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4159n_pure_kraft_hackenschmidt_NC-1024x640.webp"},
    {"model": "4307", "name": "4307 Pure Kraft Bauchmuskelbank Liegend", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4307_pure_kraft_bauchmuskelbank_NC-1024x640.webp"},
    {"model": "4311", "name": "4311 Pure Kraft Rückenzugmaschine Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4311_rueckenzugmaschine_dual_NC-1024x640.webp"},
    {"model": "4314", "name": "4314 Pure Kraft Beinpresse Sitzend Dual", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4314_pure_kraft_beinpresse_sitzend_dual_NC-1024x640.webp"},
    {"model": "4317", "name": "4317 Pure Kraft Bauchmuskelmaschine Ab Swing", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4317_pure_kraf_bauchmuskelmaschine_abswing_NC-1024x640.webp"},
    {"model": "4318", "name": "4318 Pure Kraft Bodenhantel Multi-Grip", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4318_pure_kraf_bodenhantel_multi-grip_NC-1024x640.webp"},
    {"model": "4319", "name": "4319 Pure Kraft Low Row Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4319_low_row_NC-1024x640.webp"},
    {"model": "4320", "name": "4320 Pure Kraft Schultermaschine Dual", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4320_pure_kraft_schultermaschine_dual_NC-1024x640.webp"},
    {"model": "4321", "name": "4321 Pure Kraft Gluteus Kick Maschine", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4321_pure_kraft_gluteus_kick_maschine_NC-1024x640.webp"},
    {"model": "4322", "name": "4322 Pure Kraft Rudermaschine Sitzend Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4322_pure_kraft_rudermaschine_sitzend_dual_NC-1024x640.webp"},
    {"model": "4324", "name": "4324 Pure Kraft 45 Grad Pivot Beinpresse", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4324_pure_kraft_45_grad_pivot_beinpresse_NC-1024x640.webp"},
    {"model": "4325", "name": "4325 Pure Kraft Seithebemaschine Dual", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4325_pure_kraft_seithebemaschine_dual_NC-1024x640.webp"},
    {"model": "4326", "name": "4326 Pure Kraft Brustmaschine Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4326_pure_kraf_brustmaschine_dual_NC-1024x640.webp"},
    {"model": "4327", "name": "4327 Pure Kraft Power Row Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4327_pure_kraft_power_row_dual_NC-1024x640.webp"},
    {"model": "4328", "name": "4328 Pure Kraft Bankdrückmaschine Sitzend Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4328_pure_kraft_bankdrueckmaschine_sitzend_dual_NC-1024x640.webp"},
    {"model": "4329n", "name": "4329N Pure Kraft Schrägbank Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4329n_pure_kraft_schraegbank_dual_NC-1024x640.webp"},
    {"model": "4331", "name": "4331 Pure Kraft Drückbank Liegend Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4331_pure_kraft_drueckbank_liegend_dual_NC-1024x640.webp"},
    {"model": "4332", "name": "4332 Pure Kraft Deadlift Drehgriffe Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4332_pure_kraft_deadlift_drehgriffe_dual_NC-1024x640.webp"},
    {"model": "4333", "name": "4333 Pure Kraft Deadlift Doppelgriffe Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4333_pure_kraft_deadlift_doppelgriffe_dual_NC-1024x640.webp"},
    {"model": "4335", "name": "4335 Pure Kraft Trizeps Dip Maschine Dual", "muscle": "triceps", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4335_pure_kraft_triyeps_dip_maschine_dual_NC-1024x640.webp"},
    {"model": "4336n", "name": "4336N Pure Kraft Beinstrecker", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4336n_pure_kraft_beinstreckermaschine_NC-1024x640.webp"},
    {"model": "4337n", "name": "4337N Pure Kraft Beinbeuger", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/03/1773224302828-tf638axv21.webp"},
    {"model": "4338n", "name": "4338N Pure Kraft Bizepsmaschine", "muscle": "biceps", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4338n_pure_kraft_bizepsmaschine_NC-1024x640.webp"},
    {"model": "4339n", "name": "4339N Pure Kraft Trizepsmaschine", "muscle": "triceps", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4339n_pure_kraft_trizepsmaschine_NC-1024x640.webp"},
    {"model": "4340", "name": "4340 Pure Kraft High Row Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4340_pure_kraft_high_row_dual_NC-1024x640.webp"},
    {"model": "4341", "name": "4341 Pure Kraft Butterfly Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4341_pure_kraft_butterfly_dual_NC-1024x640.webp"},
    {"model": "4342n", "name": "4342N Pure Kraft Bauchmuskelmaschine Klappsitz", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4342n_pure_kraft__klappsitz_NC-1024x640.webp"},
    {"model": "4343", "name": "4343 Pure Kraft Bauchmuskelmaschine Crunch", "muscle": "core", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4343_pure_kraft_bauchmuskelmaschine_crunch_NC-1024x640.webp"},
    {"model": "4344", "name": "4344 Pure Kraft Butterfly Reverse Dual", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4344_pure_kraft_butterfly_reverse_dual_NC-1024x640.webp"},
    {"model": "4345", "name": "4345 Pure Kraft 55 Grad Wadenmaschine Stehend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4345_pure_kraft_55_grad_wadenmaschine_NC-1024x640.webp"},
    {"model": "4346", "name": "4346 Pure Kraft Negativdrückbank Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4346_pure_kraft_negativdrueckbank_dual_NC-1024x640.webp"},
    {"model": "4348", "name": "4348 Pure Kraft Tibialismaschine Sitzend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4348_pure_kraft_tibialismaschine_sitzend_NC-1024x640.webp"},
    {"model": "4350n", "name": "4350N Pure Kraft Überzugmaschine", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4350n_pure_kraft_ueberzugmaschine_NC-1024x640.webp"},
    {"model": "4352", "name": "4352 Pure Kraft Booty Booster", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4352_pure_kraft_booty_booster_NC-1024x640.webp"},
    {"model": "4353n", "name": "4353N Pure Kraft Pendulum Squat", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4353n_pendulum_squat_NC-1024x640.webp"},
    {"model": "4354", "name": "4354 Pure Kraft Vertikale Beinpresse", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4354_pure_kraft_vertikale_beinpresse_NC-1024x640.webp"},
    {"model": "4355", "name": "4355 Pure Kraft Bizepsmaschine Dual", "muscle": "biceps", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4355_pure_kraft_bizepsmaschine_dual_NC-1024x640.webp"},
    {"model": "4360", "name": "4360 Pure Kraft Belt Squat", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4360_pure_kraft_belt_squat_NC-1024x640.webp"},
    {"model": "4361", "name": "4361 Pure Kraft-Strong Beinpresse Dual", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4361_pure_kraft_strong_beinpresse_NC-1024x640.webp"},
    {"model": "4362", "name": "4362 Pure Kraft-Strong Negativdrückbank Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4362_pure_kraft_strong_negativdrueckbank_NC-1024x640.webp"},
    {"model": "4363", "name": "4363 Pure Kraft-Strong Schulterdrückmaschine Dual", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4363_pure_kraft_strong_schulterdrueckmaschine_NC-1024x640.webp"},
    {"model": "4364", "name": "4364 Pure Kraft-Strong Drückbank Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4364_pure_kraft_strong_drueckbank_NC-1024x640.webp"},
    {"model": "4365", "name": "4365 Pure Kraft-Strong Schrägbank Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4365_pure_kraft_strong_schraegbank_NC-1024x640.webp"},
    {"model": "4366", "name": "4366 Pure Kraft Bizeps Überkopf", "muscle": "biceps", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4366_pure_kraft_bizeps_ueberkopf_NC-1024x640.webp"},
    {"model": "4371", "name": "4371 Pure Kraft Nackendrückmaschine", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4371_neckpress_NC-1024x640.webp"},
    {"model": "4372", "name": "4372 Pure Kraft Multigelenk Stehend", "muscle": "fullbody", "split": "core", "src": "https://gym80.de/wp-content/uploads/2025/07/4372_multigelenk_NC-1024x640.webp"},
    {"model": "4373", "name": "4373 Pure Kraft Beinbeuger Stehend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4373_beinbeuger_stehend_NC-1024x640.webp"},
    {"model": "4374", "name": "4374 Pure Kraft Stehende Abduktion", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4374_stehende_abduktion_NC-1024x640.webp"},
    {"model": "4375", "name": "4375 Pure Kraft Inverse Leg Curl", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4375_inverse_leg_curl_NC-1024x640.webp"},
    {"model": "4376", "name": "4376 Pure Kraft Inner Chest Liegend Dual", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4376_inner_chest_liegend_NC-1024x640.webp"},
    {"model": "4379", "name": "4379 Pure Kraft Trizeps Überkopf", "muscle": "triceps", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4379_trizeps_ueberkopf_NC-1024x640.webp"},
    {"model": "4380", "name": "4380 Pure Kraft Donkey Calf", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/07/4380_pure_kraft_donkey_calf_NC-1024x640.webp"},
    {"model": "4382", "name": "4382 Pure Kraft High Row mit beweglichen Griffen", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2025/07/4382_highrow_mit_beweglichen_griffen_NC-1024x640.webp"},
    {"model": "4383", "name": "4383 Pure Kraft 55 Grad Rudermaschine", "muscle": "back", "split": "pull", "src": "https://gym80.de/wp-content/uploads/2026/03/gym80_4383_pure_kraft_55_degree_rowing_machine_NC_overview.webp"},
    {"model": "4384", "name": "4384 Pure Kraft Abduktion 3D", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/11/4384_pure_kraft_abduction_3d_NC-1024x640.webp"},
    {"model": "4385", "name": "4385 Pure Kraft Seithebemaschine Stehend", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/11/4385_standing_shoulder_lateral_raise_NC-1024x640.webp"},
    {"model": "4386", "name": "4386 Pure Kraft Booty Booster Special", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2025/11/4386_booty_booster_special_NC-1024x640.webp"},
    {"model": "4386n", "name": "4386N Pure Kraft Booty Booster Special (NEW)", "muscle": "glutes", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/04/Comig-soonv2-4386N.webp"},
    {"model": "4388", "name": "4388 Pure Kraft Viking Press", "muscle": "shoulders", "split": "push", "src": "https://gym80.de/wp-content/uploads/2025/07/4388_viking_press_NC-1024x640.webp"},
    {"model": "4389", "name": "4389 Pure Kraft Leverage Squat", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/04/gym80_4389_leverage_squat_overview.webp"},
    {"model": "4390", "name": "4390 Pure Kraft Butterfly 50 Grad", "muscle": "chest", "split": "push", "src": "https://gym80.de/wp-content/uploads/2026/04/Comig-soonv2-4390.webp"},
    {"model": "4391", "name": "4391 Pure Kraft 3D Leg Machine", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/04/Comig-soonv2-4391.webp"},
    {"model": "4392", "name": "4392 Pure Kraft Beinstrecker Stehend", "muscle": "legs", "split": "legs", "src": "https://gym80.de/wp-content/uploads/2026/04/Comig-soonv2-4392.webp"},
]


def seed_exercises() -> None:
    inserted = 0
    skipped = 0
    with SessionLocal() as db:
        existing_names = {row[0] for row in db.query(Exercise.name).all()}
        for entry in GYM80_CATALOG:
            if entry["name"] in existing_names:
                skipped += 1
                continue
            exercise = Exercise(
                id=uuid4(),
                name=entry["name"],
                equipment="machine",
                primary_muscle_group=entry["muscle"],
                default_split_tag=entry["split"],
                image_url=f"/images/exercises/{entry['model']}.webp",
                is_seeded=True,
                created_by_user_id=None,
            )
            db.add(exercise)
            inserted += 1
        db.commit()

    print(f"✓ Gym80 catalog seeded: {inserted} inserted, {skipped} already present (total catalog: {len(GYM80_CATALOG)})")


if __name__ == "__main__":
    seed_exercises()
