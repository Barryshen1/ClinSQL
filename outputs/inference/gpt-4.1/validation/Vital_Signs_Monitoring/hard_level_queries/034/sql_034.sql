WITH
-- 1. Identify itemids for MAP and HR
map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
hr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),

-- 2. Identify mixed shock ICD codes
mixed_shock_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%shock%' AND (
    LOWER(long_title) LIKE '%mixed%' OR
    LOWER(long_title) LIKE '%not elsewhere classified%' OR
    LOWER(long_title) LIKE '%other%'
  )
  -- Add specific codes if needed
  UNION ALL SELECT 'R57.2', 10
  UNION ALL SELECT '785.59', 9
),

-- 3. Cohort selection: Female ICU patients 60-70 with mixed shock
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  JOIN mixed_shock_icds ms
    ON diag.icd_code = ms.icd_code AND diag.icd_version = ms.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 60 AND 70
),

-- 4. Get MAP and HR measurements in first 48h of ICU stay
vitals AS (
  SELECT
    c.stay_id,
    c.intime,
    ce.charttime,
    CASE WHEN ce.itemid IN (SELECT itemid FROM map_items) THEN ce.valuenum END AS map_value,
    CASE WHEN ce.itemid IN (SELECT itemid FROM hr_items) THEN ce.valuenum END AS hr_value
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- 5. For each stay, aggregate hourly instability (MAP<65 or HR>100)
hourly_instability AS (
  SELECT
    stay_id,
    DATETIME_TRUNC(charttime, HOUR) AS hour,
    MAX(IF(map_value IS NOT NULL AND map_value < 65, 1, 0)) AS hypotension,
    MAX(IF(hr_value IS NOT NULL AND hr_value > 100, 1, 0)) AS tachycardia,
    MAX(
      IF(
        (map_value IS NOT NULL AND map_value < 65) OR (hr_value IS NOT NULL AND hr_value > 100),
        1, 0
      )
    ) AS instability
  FROM vitals
  GROUP BY stay_id, hour
),

-- 6. Calculate instability score (sum of hours with instability in first 48h)
instability_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    c.anchor_age,
    c.gender,
    c.hospital_expire_flag,
    COUNTIF(instability = 1) AS instability_score,
    COUNTIF(hypotension = 1) AS hypotension_hours,
    COUNTIF(tachycardia = 1) AS tachycardia_hours,
    COUNT(*) AS total_hours
  FROM cohort c
  LEFT JOIN hourly_instability hi
    ON c.stay_id = hi.stay_id
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime, c.los, c.anchor_age, c.gender, c.hospital_expire_flag
),

-- 7. Calculate percentiles for instability score
percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[95] AS p95,
    APPROX_QUANTILES(instability_score, 10)[9] AS p90
  FROM instability_scores
),

-- 8. Mark top decile
scored_cohort AS (
  SELECT
    s.*,
    p.p95,
    p.p90,
    CASE WHEN s.instability_score >= p.p90 THEN 1 ELSE 0 END AS top_decile
  FROM instability_scores s
  CROSS JOIN percentiles p
),

-- 9. Aggregate metrics for cohort and top decile
metrics AS (
  SELECT
    'Cohort' AS group_type,
    COUNT(*) AS n_stays,
    AVG(CAST(hypotension_hours AS FLOAT64) / NULLIF(total_hours,0)) AS frac_hypotension,
    AVG(CAST(tachycardia_hours AS FLOAT64) / NULLIF(total_hours,0)) AS frac_tachycardia,
    AVG(los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM scored_cohort
  UNION ALL
  SELECT
    'Top Decile' AS group_type,
    COUNT(*) AS n_stays,
    AVG(CAST(hypotension_hours AS FLOAT64) / NULLIF(total_hours,0)) AS frac_hypotension,
    AVG(CAST(tachycardia_hours AS FLOAT64) / NULLIF(total_hours,0)) AS frac_tachycardia,
    AVG(los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM scored_cohort
  WHERE top_decile = 1
)

-- Final output: 95th percentile instability score, metrics for cohort and top decile
SELECT
  p.p95 AS cohort_95th_percentile_instability_score,
  m.*
FROM percentiles p
CROSS JOIN metrics m
ORDER BY
  CASE WHEN m.group_type = 'Top Decile' THEN 1 ELSE 0 END,
  m.group_type;