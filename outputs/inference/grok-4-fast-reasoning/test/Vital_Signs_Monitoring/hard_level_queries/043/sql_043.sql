WITH resp_hadms AS (
  -- Identify admissions with respiratory failure diagnosis
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code = '518.81' OR icd_code = '518.82' OR icd_code = '518.84' OR icd_code = '799.1'))
     OR (icd_version = 10 AND (icd_code = 'J80' OR icd_code LIKE 'J96%'))
),
full_stays AS (
  -- All ICU stays for resp failure patients
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN resp_hadms rh ON i.subject_id = rh.subject_id AND i.hadm_id = rh.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE i.los > 0  -- Valid ICU stays
),
sub_stays AS (
  -- Subcohort: males 40-50y
  SELECT * FROM full_stays
  WHERE gender = 'M' AND anchor_age BETWEEN 40 AND 50
),
-- HR data for VII and tachycardic burden (itemid 220045)
hr_data AS (
  SELECT 
    stay_id,
    charttime,
    valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid = 220045  -- Heart Rate
    AND valuenum IS NOT NULL
),
-- VII per stay (STDDEV of HR)
vii_per_stay AS (
  SELECT 
    s.stay_id,
    STDDEV(h.valuenum) AS vii  -- SD of HR as instability index
  FROM sub_stays s
  INNER JOIN hr_data h ON s.stay_id = h.stay_id
  WHERE h.charttime >= s.intime 
    AND h.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 2 DAY)
  GROUP BY s.stay_id
  HAVING COUNT(h.valuenum) >= 2  -- Need variance
),
-- MAP data for hypotensive burden (itemid 220052)
map_data AS (
  SELECT 
    stay_id,
    charttime,
    valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid = 220052  -- Arterial BP Mean
    AND valuenum IS NOT NULL
),
-- HR data filtered to 48h for sub/full (for tachy in sub, but compute for both)
hr_48h AS (
  SELECT 
    f.stay_id,
    f.intime,
    h.charttime,
    h.valuenum
  FROM full_stays f  -- For both cohorts
  INNER JOIN hr_data h ON f.stay_id = h.stay_id
  WHERE h.charttime >= f.intime 
    AND h.charttime <= TIMESTAMP_ADD(f.intime, INTERVAL 2 DAY)
),
hr_48h_with_lead AS (
  SELECT 
    stay_id,
    intime,
    charttime,
    valuenum,
    LEAD(charttime) OVER (PARTITION BY stay_id ORDER BY charttime) AS next_charttime
  FROM hr_48h
),
hr_48h_intervals AS (
  SELECT 
    stay_id,
    CASE 
      WHEN next_charttime IS NOT NULL THEN TIMESTAMP_DIFF(next_charttime, charttime, MINUTE)
      ELSE TIMESTAMP_DIFF(TIMESTAMP_ADD(intime, INTERVAL 48 HOUR), charttime, MINUTE)
    END AS interval_min,
    valuenum
  FROM hr_48h_with_lead
  WHERE CASE 
      WHEN next_charttime IS NOT NULL THEN TIMESTAMP_DIFF(next_charttime, charttime, MINUTE) > 0
      ELSE TIMESTAMP_DIFF(TIMESTAMP_ADD(intime, INTERVAL 48 HOUR), charttime, MINUTE) > 0
    END
),
tachy_burden_48h AS (
  SELECT 
    stay_id,
    SAFE_DIVIDE(
      SUM(CASE WHEN valuenum > 100 THEN interval_min ELSE 0 END), 
      SUM(interval_min)
    ) * 100 AS tachy_burden_pct_48h
  FROM hr_48h_intervals
  GROUP BY stay_id
  HAVING SUM(interval_min) > 0  -- Has observations
),
-- MAP 48h for hypo
map_48h AS (
  SELECT 
    f.stay_id,
    f.intime,
    m.charttime,
    m.valuenum
  FROM full_stays f
  INNER JOIN map_data m ON f.stay_id = m.stay_id
  WHERE m.charttime >= f.intime 
    AND m.charttime <= TIMESTAMP_ADD(f.intime, INTERVAL 2 DAY)
),
map_48h_with_lead AS (
  SELECT 
    stay_id,
    intime,
    charttime,
    valuenum,
    LEAD(charttime) OVER (PARTITION BY stay_id ORDER BY charttime) AS next_charttime
  FROM map_48h
),
map_48h_intervals AS (
  SELECT 
    stay_id,
    CASE 
      WHEN next_charttime IS NOT NULL THEN TIMESTAMP_DIFF(next_charttime, charttime, MINUTE)
      ELSE TIMESTAMP_DIFF(TIMESTAMP_ADD(intime, INTERVAL 48 HOUR), charttime, MINUTE)
    END AS interval_min,
    valuenum
  FROM map_48h_with_lead
  WHERE CASE 
      WHEN next_charttime IS NOT NULL THEN TIMESTAMP_DIFF(next_charttime, charttime, MINUTE) > 0
      ELSE TIMESTAMP_DIFF(TIMESTAMP_ADD(intime, INTERVAL 48 HOUR), charttime, MINUTE) > 0
    END
),
hypo_burden_48h AS (
  SELECT 
    stay_id,
    SAFE_DIVIDE(
      SUM(CASE WHEN valuenum < 65 THEN interval_min ELSE 0 END), 
      SUM(interval_min)
    ) * 100 AS hypo_burden_pct_48h
  FROM map_48h_intervals
  GROUP BY stay_id
  HAVING SUM(interval_min) > 0
),
-- Aggregate for subcohort VII stats
vii_stats AS (
  SELECT 
    STDDEV(vii) AS vii_sd,
    PERCENTILE_CONT(vii, 0.25) AS vii_p25,
    PERCENTILE_CONT(vii, 0.50) AS vii_p50,
    PERCENTILE_CONT(vii, 0.75) AS vii_p75,
    PERCENTILE_CONT(vii, 0.95) AS vii_p95
  FROM vii_per_stay
),
-- Join burdens/LOS/mort to cohorts (use LEFT JOIN, default 0 for missing burdens)
sub_metrics AS (
  SELECT 
    'Subcohort' AS cohort,
    s.stay_id,
    COALESCE(hb.hypo_burden_pct_48h, 0) AS hypo_burden_pct,
    COALESCE(tb.tachy_burden_pct_48h, 0) AS tachy_burden_pct,
    s.los,
    s.hospital_expire_flag
  FROM sub_stays s
  LEFT JOIN hypo_burden_48h hb ON s.stay_id = hb.stay_id
  LEFT JOIN tachy_burden_48h tb ON s.stay_id = tb.stay_id
),
full_metrics AS (
  SELECT 
    'Full' AS cohort,
    f.stay_id,
    COALESCE(hb.hypo_burden_pct_48h, 0) AS hypo_burden_pct,
    COALESCE(tb.tachy_burden_pct_48h, 0) AS tachy_burden_pct,
    f.los,
    f.hospital_expire_flag
  FROM full_stays f
  LEFT JOIN hypo_burden_48h hb ON f.stay_id = hb.stay_id
  LEFT JOIN tachy_burden_48h tb ON f.stay_id = tb.stay_id
),
all_metrics AS (
  SELECT * FROM sub_metrics
  UNION ALL
  SELECT * FROM full_metrics
),
-- Comparisons: means, medians, % mort
comparisons AS (
  SELECT 
    cohort,
    AVG(hypo_burden_pct) AS mean_hypo_burden_pct,
    PERCENTILE_CONT(hypo_burden_pct, 0.5) AS median_hypo_burden_pct,
    AVG(tachy_burden_pct) AS mean_tachy_burden_pct,
    PERCENTILE_CONT(tachy_burden_pct, 0.5) AS median_tachy_burden_pct,
    AVG(los) AS mean_los,
    PERCENTILE_CONT(los, 0.5) AS median_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mort_pct
  FROM all_metrics
  GROUP BY cohort
)
-- Final output: VII stats (sub only) + comparisons
SELECT 
  'Subcohort (Males 40-50y)' AS group_desc,
  vs.vii_sd,
  vs.vii_p25,
  vs.vii_p50,
  vs.vii_p75,
  vs.vii_p95,
  c.mean_hypo_burden_pct,
  c.median_hypo_burden_pct,
  c.mean_tachy_burden_pct,
  c.median_tachy_burden_pct,
  c.mean_los,
  c.median_los,
  c.mort_pct
FROM vii_stats vs
CROSS JOIN (SELECT * FROM comparisons WHERE cohort = 'Subcohort') c

UNION ALL

SELECT 
  'Full Cohort (All Resp Failure)' AS group_desc,
  NULL AS vii_sd,  -- Not computed for full
  NULL AS vii_p25,
  NULL AS vii_p50,
  NULL AS vii_p75,
  NULL AS vii_p95,
  c.mean_hypo_burden_pct,
  c.median_hypo_burden_pct,
  c.mean_tachy_burden_pct,
  c.median_tachy_burden_pct,
  c.mean_los,
  c.median_los,
  c.mort_pct
FROM (SELECT * FROM comparisons WHERE cohort = 'Full') c;