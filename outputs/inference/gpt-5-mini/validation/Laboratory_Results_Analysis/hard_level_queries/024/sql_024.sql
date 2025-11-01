WITH
-- 1) Identify female patients age 53-63
female_patients AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 53 AND 63
),

-- 2) Identify admissions for those patients that have a cardiac arrest diagnosis on that admission
post_arrest_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_patients fp
    ON a.subject_id = fp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%cardiac arrest%'
),

-- 3) Candidate lab itemids (common post-arrest critical labs)
candidate_labs AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%potassium%'
     OR LOWER(label) LIKE '%sodium%'
     OR LOWER(label) LIKE '%creatinine%'
     OR LOWER(label) LIKE '%lactate%'
     OR LOWER(label) LIKE '%hemoglobin%'
     OR LOWER(label) LIKE '%hgb%'
     OR LOWER(label) LIKE '%glucose%'
     OR LOWER(label) LIKE '%bicarbonate%'
     OR LOWER(label) LIKE '%co2%'
     OR LOWER(label) LIKE '%ph%'
),

-- 4) Lab measurements in the first 48 hours of admission for the post-arrest cohort
labs_48h AS (
  SELECT
    pa.hadm_id,
    le.subject_id,
    le.itemid,
    le.charttime,
    SAFE_CAST(le.valuenum AS FLOAT64) AS valuenum,
    SAFE_CAST(le.ref_range_lower AS FLOAT64) AS ref_low,
    SAFE_CAST(le.ref_range_upper AS FLOAT64) AS ref_high
  FROM post_arrest_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pa.hadm_id = le.hadm_id
  JOIN candidate_labs cl
    ON le.itemid = cl.itemid
  WHERE le.charttime BETWEEN pa.admittime AND TIMESTAMP_ADD(pa.admittime, INTERVAL 48 HOUR)
    AND SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
),

-- 5) Per-admission & per-item lab min/max and normalized delta
per_lab_delta AS (
  SELECT
    hadm_id,
    itemid,
    MIN(valuenum) AS min_val,
    MAX(valuenum) AS max_val,
    MIN(ref_low) AS ref_low_min,
    MAX(ref_high) AS ref_high_max,
    ABS(MAX(valuenum) - MIN(valuenum)) AS delta,
    CASE
      WHEN (MAX(ref_high) IS NULL OR MIN(ref_low) IS NULL OR (MAX(ref_high) - MIN(ref_low)) = 0) THEN
        ABS(MAX(valuenum) - MIN(valuenum))
      ELSE
        ABS(MAX(valuenum) - MIN(valuenum)) / CAST((MAX(ref_high) - MIN(ref_low)) AS FLOAT64)
    END AS delta_norm
  FROM labs_48h
  GROUP BY hadm_id, itemid
),

-- 6) Per-admission lab instability score (sum of normalized deltas across included labs)
admission_instability AS (
  SELECT
    hadm_id,
    SUM(delta_norm) AS instability_score
  FROM per_lab_delta
  GROUP BY hadm_id
),

-- 7) 90th percentile threshold across the cohort
percentile_90 AS (
  SELECT
    (APPROX_QUANTILES(instability_score, 100))[OFFSET(90)] AS p90
  FROM admission_instability
),

-- 8) Admissions with score >= 90th percentile
high_instability_admissions AS (
  SELECT ai.hadm_id, ai.instability_score
  FROM admission_instability ai
  CROSS JOIN percentile_90 p
  WHERE ai.instability_score >= p.p90
),

-- 9) For mortality and LOS, join back to admissions table to get hospital_expire_flag and dischtime/admittime
high_instability_stats AS (
  SELECT
    h.hadm_id,
    h.instability_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)/86400.0 AS los_days
  FROM high_instability_admissions h
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON h.hadm_id = a.hadm_id
),

-- 10) Critical lab event detection within first 48 hours:
-- A "critical" lab measurement is one where valuenum < ref_low OR valuenum > ref_high,
-- and ref_low/ref_high are present (we only count events where ref ranges are present).
critical_labs_48h AS (
  SELECT
    le.hadm_id,
    le.subject_id,
    le.itemid,
    SAFE_CAST(le.valuenum AS FLOAT64) AS valuenum,
    SAFE_CAST(le.ref_range_lower AS FLOAT64) AS ref_low,
    SAFE_CAST(le.ref_range_upper AS FLOAT64) AS ref_high
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN candidate_labs cl
    ON le.itemid = cl.itemid
  WHERE SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(le.ref_range_lower AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(le.ref_range_upper AS FLOAT64) IS NOT NULL
    -- first 48 hours relative to admission time: join to admissions to get admittime
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
      WHERE a.hadm_id = le.hadm_id
        AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    )
),

-- 11) For each admission, whether it had any candidate lab in first 48h (with ref ranges available)
admission_has_any_candidate_lab AS (
  SELECT DISTINCT hadm_id
  FROM critical_labs_48h
),

-- 12) For each admission, whether it had at least one critical lab in first 48h
admission_has_critical_lab AS (
  SELECT DISTINCT hadm_id
  FROM critical_labs_48h
  WHERE valuenum < ref_low OR valuenum > ref_high
),

-- 13) Subgroup metrics: counts of admissions with labs and with critical labs among high-instability admissions
subgroup_critical_counts AS (
  SELECT
    COUNT(DISTINCT h.hadm_id) AS subgroup_total_high_instability,
    COUNT(DISTINCT ah.hadm_id) AS subgroup_had_any_candidate_lab,
    COUNT(DISTINCT ac.hadm_id) AS subgroup_had_critical_lab
  FROM high_instability_admissions h
  LEFT JOIN admission_has_any_candidate_lab ah
    ON h.hadm_id = ah.hadm_id
  LEFT JOIN admission_has_critical_lab ac
    ON h.hadm_id = ac.hadm_id
),

-- 14) Overall (all adult inpatients) metrics: counts of admissions with labs and with critical labs
all_adult_admissions AS (
  -- define "all inpatients" here as adult admissions (anchor_age >= 18)
  SELECT a.hadm_id, a.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age >= 18
),
all_critical_counts AS (
  SELECT
    (SELECT COUNT(DISTINCT hadm_id) FROM all_adult_admissions) AS all_adult_admissions_n,
    (SELECT COUNT(DISTINCT ac.hadm_id)
     FROM admission_has_any_candidate_lab ac
     JOIN all_adult_admissions aa ON ac.hadm_id = aa.hadm_id
    ) AS all_adult_had_any_candidate_lab,
    (SELECT COUNT(DISTINCT ac2.hadm_id)
     FROM admission_has_critical_lab ac2
     JOIN all_adult_admissions aa2 ON ac2.hadm_id = aa2.hadm_id
    ) AS all_adult_had_critical_lab
)

-- Final output: combine percentile, subgroup summary, mortality/LOS, and critical lab comparison
SELECT
  p.p90 AS instability_score_90th_percentile,

  -- subgroup counts & outcomes
  sic.subgroup_total_high_instability AS subgroup_count_ge_90th,
  -- mortality among high-instability admissions
  SUM(CASE WHEN his.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS subgroup_inhospital_deaths,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN his.hospital_expire_flag = 1 THEN 1 ELSE 0 END), NULLIF(sic.subgroup_total_high_instability,0)), 2)
    AS subgroup_mortality_percent,
  ROUND(AVG(his.los_days), 3) AS subgroup_mean_los_days,

  -- critical lab frequencies (subgroup)
  sic.subgroup_had_any_candidate_lab AS subgroup_n_with_any_candidate_lab_48h,
  sic.subgroup_had_critical_lab AS subgroup_n_with_critical_lab_48h,
  ROUND(100.0 * SAFE_DIVIDE(sic.subgroup_had_critical_lab, NULLIF(sic.subgroup_had_any_candidate_lab,0)), 2)
    AS subgroup_critical_lab_pct_among_those_with_labs,

  -- overall adult inpatient critical lab frequencies
  ac.all_adult_admissions_n AS all_adult_inpatient_admissions,
  ac.all_adult_had_any_candidate_lab AS all_adult_n_with_any_candidate_lab_48h,
  ac.all_adult_had_critical_lab AS all_adult_n_with_critical_lab_48h,
  ROUND(100.0 * SAFE_DIVIDE(ac.all_adult_had_critical_lab, NULLIF(ac.all_adult_had_any_candidate_lab,0)), 2)
    AS all_adult_critical_lab_pct_among_those_with_labs

FROM percentile_90 p
LEFT JOIN high_instability_stats his
  ON TRUE
LEFT JOIN subgroup_critical_counts sic
  ON TRUE
LEFT JOIN all_critical_counts ac
  ON TRUE
GROUP BY
  p.p90,
  sic.subgroup_total_high_instability,
  sic.subgroup_had_any_candidate_lab,
  sic.subgroup_had_critical_lab,
  ac.all_adult_admissions_n,
  ac.all_adult_had_any_candidate_lab,
  ac.all_adult_had_critical_lab
LIMIT 1;