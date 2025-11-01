WITH ugib_cohort AS (
  SELECT DISTINCT i.stay_id, i.subject_id, i.hadm_id, i.intime, p.anchor_age, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = i.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN ('K25.0', 'K25.4', 'K26.0', 'K26.4', 'K27.0', 'K27.4', 'K28.0', 'K28.4', 'I85.01', 'K92.0')
    )
),
control_cohort AS (
  SELECT DISTINCT i.stay_id, i.subject_id, i.hadm_id, i.intime, p.anchor_age, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = i.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN ('K25.0', 'K25.4', 'K26.0', 'K26.4', 'K27.0', 'K27.4', 'K28.0', 'K28.4', 'I85.01', 'K92.0')
    )
),
first48_vitals_ugib AS (
  SELECT ce.stay_id, ce.charttime, ce.itemid, ce.valuenum
  FROM ugib_cohort uc
  JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce ON ce.stay_id = uc.stay_id
  WHERE ce.charttime >= uc.intime
    AND ce.charttime <= uc.intime + INTERVAL 48 HOUR
    AND ce.itemid IN (220045, 220052, 220210)
    AND ce.valuenum IS NOT NULL
),
unstable_events_ugib AS (
  SELECT 
    stay_id,
    DATE_TRUNC(charttime, HOUR) AS hour_bin
  FROM first48_vitals_ugib
  WHERE (itemid = 220045 AND valuenum > 100)
     OR (itemid = 220052 AND valuenum < 65)
     OR (itemid = 220210 AND valuenum > 20)
),
instability_index_ugib AS (
  SELECT stay_id, COUNT(DISTINCT hour_bin) AS instability_index
  FROM unstable_events_ugib
  GROUP BY stay_id
),
ugib_with_index AS (
  SELECT uc.*, COALESCE(ii.instability_index, 0) AS instability_index, i.los
  FROM ugib_cohort uc
  JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON i.stay_id = uc.stay_id
  LEFT JOIN instability_index_ugib ii ON ii.stay_id = uc.stay_id
),
p90_val AS (
  SELECT APPROX_QUANTILES(instability_index, 100)[OFFSET(90)] AS threshold
  FROM ugib_with_index
),
top_decile_ugib AS (
  SELECT uwi.*
  FROM ugib_with_index uwi
  CROSS JOIN p90_val p
  WHERE uwi.instability_index >= p.threshold
),
first48_flags AS (
  SELECT 
    ce.stay_id,
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS has_tachycardia,
    MAX(CASE WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS has_low_map,
    MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS has_tachypnea
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON ce.stay_id = i.stay_id
  WHERE ce.itemid IN (220045, 220052, 220210) AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.intime + INTERVAL 48 HOUR
  GROUP BY ce.stay_id
),
top_decile_with_flags AS (
  SELECT td.*, f.has_tachycardia, f.has_low_map, f.has_tachypnea
  FROM top_decile_ugib td
  LEFT JOIN first48_flags f ON f.stay_id = td.stay_id
),
control_with_flags AS (
  SELECT cc.*, i.los, COALESCE(f.has_tachycardia, 0) AS has_tachycardia, 
         COALESCE(f.has_low_map, 0) AS has_low_map, COALESCE(f.has_tachypnea, 0) AS has_tachypnea
  FROM control_cohort cc
  JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON i.stay_id = cc.stay_id
  LEFT JOIN first48_flags f ON f.stay_id = cc.stay_id
),
ugib_top_summary AS (
  SELECT 
    COUNT(*) AS n_ugib_top,
    AVG(CASE WHEN has_tachycardia = 1 THEN 1.0 ELSE 0 END) AS tachy_rate,
    AVG(CASE WHEN has_low_map = 1 THEN 1.0 ELSE 0 END) AS lowmap_rate,
    AVG(CASE WHEN has_tachypnea = 1 THEN 1.0 ELSE 0 END) AS tachyp_rate,
    AVG(los) AS avg_los,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mort_rate
  FROM top_decile_with_flags
),
control_summary AS (
  SELECT 
    COUNT(*) AS n_control,
    AVG(CASE WHEN has_tachycardia = 1 THEN 1.0 ELSE 0 END) AS tachy_rate,
    AVG(CASE WHEN has_low_map = 1 THEN 1.0 ELSE 0 END) AS lowmap_rate,
    AVG(CASE WHEN has_tachypnea = 1 THEN 1.0 ELSE 0 END) AS tachyp_rate,
    AVG(los) AS avg_los,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mort_rate
  FROM control_with_flags
),
p95_summary AS (
  SELECT APPROX_QUANTILES(instability_index, 100)[OFFSET(95)] AS p95_instability
  FROM ugib_with_index
)
SELECT 
  p95.p95_instability,
  uts.tachy_rate AS ugib_top_tachy_rate,
  cs.tachy_rate AS control_tachy_rate,
  uts.lowmap_rate AS ugib_top_lowmap_rate,
  cs.lowmap_rate AS control_lowmap_rate,
  uts.tachyp_rate AS ugib_top_tachyp_rate,
  cs.tachyp_rate AS control_tachyp_rate,
  uts.avg_los AS ugib_top_avg_los,
  cs.avg_los AS control_avg_los,
  uts.mort_rate AS ugib_top_mort_rate,
  cs.mort_rate AS control_mort_rate,
  uts.n_ugib_top,
  cs.n_control
FROM p95_summary p95
CROSS JOIN ugib_top_summary uts
CROSS JOIN control_summary cs;