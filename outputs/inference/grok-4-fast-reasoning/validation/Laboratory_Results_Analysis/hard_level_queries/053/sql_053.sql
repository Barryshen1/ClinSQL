WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
cr_critical AS (
  SELECT DISTINCT le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c ON le.hadm_id = c.hadm_id
  WHERE le.itemid = 50912
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 3.0
    AND le.valueuom IN ('mg/dL', 'mg/dl')
),
k_critical AS (
  SELECT DISTINCT le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c ON le.hadm_id = c.hadm_id
  WHERE le.itemid = 50971
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (le.valuenum < 2.5 OR le.valuenum > 6.0)
    AND le.valueuom = 'mEq/L'
),
platelets_critical AS (
  SELECT DISTINCT le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c ON le.hadm_id = c.hadm_id
  WHERE le.itemid = 51265
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (le.valuenum < 20 OR le.valuenum > 1000)
    AND le.valueuom = 'K/uL'
),
hgb_critical AS (
  SELECT DISTINCT le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c ON le.hadm_id = c.hadm_id
  WHERE le.itemid = 51221
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.valuenum < 7.0
    AND le.valueuom = 'g/dL'
),
wbc_critical AS (
  SELECT DISTINCT le.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN cohort c ON le.hadm_id = c.hadm_id
  WHERE le.itemid = 51301
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (le.valuenum < 1.0 OR le.valuenum > 50.0)
    AND le.valueuom = 'K/uL'
),
wbk_critical AS (
  SELECT DISTINCT ce.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c ON ce.hadm_id = c.hadm_id
  WHERE ce.itemid = 846
    AND ce.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND (ce.valuenum < 2.5 OR ce.valuenum > 6.0)
    AND ce.valueuom = 'mEq/L'
),
base AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    c.admittime,
    c.dischtime,
    (CASE WHEN cr.hadm_id IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN k.hadm_id IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN plat.hadm_id IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN hgb.hadm_id IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN wbc.hadm_id IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN wbk.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS score
  FROM cohort c
  LEFT JOIN cr_critical cr ON c.hadm_id = cr.hadm_id
  LEFT JOIN k_critical k ON c.hadm_id = k.hadm_id
  LEFT JOIN platelets_critical plat ON c.hadm_id = plat.hadm_id
  LEFT JOIN hgb_critical hgb ON c.hadm_id = hgb.hadm_id
  LEFT JOIN wbc_critical wbc ON c.hadm_id = wbc.hadm_id
  LEFT JOIN wbk_critical wbk ON c.hadm_id = wbk.hadm_id
),
p90 AS (
  SELECT APPROX_QUANTILES(score, 100)[OFFSET(90)] AS p90_score
  FROM base
),
top_tier AS (
  SELECT b.*
  FROM base b
  CROSS JOIN p90 p
  WHERE b.score >= p.p90_score
)
SELECT
  p.p90_score AS percentile_90_lab_instability_score,
  (SELECT AVG(hospital_expire_flag) FROM top_tier) AS top_tier_mortality_rate,
  (SELECT AVG(DATE_DIFF(dischtime, admittime, HOUR) / 24.0) FROM top_tier) AS top_tier_avg_los_days,
  -- All cohort critical rates (%)
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM base) FROM cr_critical) AS all_cr_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM base) FROM k_critical) AS all_k_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM base) FROM platelets_critical) AS all_platelets_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM base) FROM hgb_critical) AS all_hgb_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM base) FROM wbc_critical) AS all_wbc_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM base) FROM wbk_critical) AS all_whole_blood_k_critical_rate,
  -- Top-tier critical rates (%)
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM top_tier)
   FROM cr_critical cr INNER JOIN top_tier tt ON cr.hadm_id = tt.hadm_id) AS top_cr_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM top_tier)
   FROM k_critical k INNER JOIN top_tier tt ON k.hadm_id = tt.hadm_id) AS top_k_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM top_tier)
   FROM platelets_critical plat INNER JOIN top_tier tt ON plat.hadm_id = tt.hadm_id) AS top_platelets_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM top_tier)
   FROM hgb_critical hgb INNER JOIN top_tier tt ON hgb.hadm_id = tt.hadm_id) AS top_hgb_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM top_tier)
   FROM wbc_critical wbc INNER JOIN top_tier tt ON wbc.hadm_id = tt.hadm_id) AS top_wbc_critical_rate,
  (SELECT COUNT(*) * 100.0 / (SELECT COUNT(*) FROM top_tier)
   FROM wbk_critical wbk INNER JOIN top_tier tt ON wbk.hadm_id = tt.hadm_id) AS top_whole_blood_k_critical_rate
FROM p90 p;