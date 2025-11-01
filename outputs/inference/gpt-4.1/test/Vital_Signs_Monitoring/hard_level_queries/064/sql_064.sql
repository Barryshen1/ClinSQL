WITH map_hr_items AS (
  SELECT
    itemid,
    CASE
      WHEN LOWER(label) LIKE '%mean arterial%' OR LOWER(label) LIKE '%map%' THEN 'MAP'
      WHEN LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr%' THEN 'HR'
      ELSE NULL
    END AS vital
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%mean arterial%' OR LOWER(label) LIKE '%map%'
     OR LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr%'
),
-- Step 2: Get ARF ICD codes
arf_icds AS (
  SELECT DISTINCT icd_code, icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE
    (icd_version = 9 AND (icd_code LIKE '51881' OR icd_code LIKE '51882' OR icd_code LIKE '51884'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'J96%' OR icd_code LIKE 'J960%' OR icd_code LIKE 'J961%' OR icd_code LIKE 'J969%'))
),
-- Step 3: Identify ARF ICU stays for male patients 45-55
arf_icu_cohort AS (
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
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON icu.hadm_id = diag.hadm_id
  JOIN arf_icds
    ON diag.icd_code = arf_icds.icd_code AND diag.icd_version = arf_icds.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
),
-- Step 4: Get MAP and HR measurements in first 48h of ICU stay
vitals_48h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    i.vital
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  JOIN map_hr_items i
    ON c.itemid = i.itemid
  JOIN arf_icu_cohort icu
    ON c.stay_id = icu.stay_id
  WHERE c.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
),
-- Step 5: Calculate instability flags per measurement
instability_flags AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    MAX(CASE WHEN vital = 'MAP' AND valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_flag,
    MAX(CASE WHEN vital = 'HR' AND valuenum > 100 THEN 1 ELSE 0 END) AS tachy_flag
  FROM vitals_48h
  GROUP BY subject_id, hadm_id, stay_id, charttime
),
-- Step 6: Composite instability score per ICU stay (sum of flags in first 48h)
instability_score AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    SUM(hypotension_flag + tachy_flag) AS composite_score,
    MAX(hypotension_flag) AS had_hypotension,
    MAX(tachy_flag) AS had_tachycardia
  FROM instability_flags
  GROUP BY stay_id, subject_id, hadm_id
),
-- Step 7: Merge with cohort and LOS/mortality
arf_icu_scores AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.anchor_age,
    icu.gender,
    icu.los,
    icu.hospital_expire_flag,
    s.composite_score,
    s.had_hypotension,
    s.had_tachycardia
  FROM arf_icu_cohort icu
  LEFT JOIN instability_score s
    ON icu.stay_id = s.stay_id
),
-- Step 8: Calculate percentiles for composite score
percentiles AS (
  SELECT
    APPROX_QUANTILES(composite_score, 100)[SAFE_OFFSET(95)] AS p95,
    APPROX_QUANTILES(composite_score, 4)[SAFE_OFFSET(3)] AS p75
  FROM arf_icu_scores
  WHERE composite_score IS NOT NULL
),
-- Step 9: Mark top quartile
arf_icu_scores_quartile AS (
  SELECT
    a.*,
    CASE WHEN a.composite_score >= (SELECT p75 FROM percentiles) THEN 'top_quartile' ELSE 'rest' END AS quartile
  FROM arf_icu_scores a
),
-- Step 10: Age-matched cohort (male ICU patients 45-55, no ARF required)
age_matched_icu_full AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    pat.anchor_age,
    pat.gender,
    icu.los,
    adm.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 45 AND 55
),
age_matched_vitals_48h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    i.vital
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  JOIN map_hr_items i
    ON c.itemid = i.itemid
  JOIN age_matched_icu_full icu
    ON c.stay_id = icu.stay_id
  WHERE c.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
),
age_matched_instability_flags AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    MAX(CASE WHEN vital = 'MAP' AND valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_flag,
    MAX(CASE WHEN vital = 'HR' AND valuenum > 100 THEN 1 ELSE 0 END) AS tachy_flag
  FROM age_matched_vitals_48h
  GROUP BY subject_id, hadm_id, stay_id, charttime
),
age_matched_instability_score AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    SUM(hypotension_flag + tachy_flag) AS composite_score,
    MAX(hypotension_flag) AS had_hypotension,
    MAX(tachy_flag) AS had_tachycardia
  FROM age_matched_instability_flags
  GROUP BY stay_id, subject_id, hadm_id
),
age_matched_icu_scores AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.anchor_age,
    icu.gender,
    icu.los,
    icu.hospital_expire_flag,
    s.composite_score,
    s.had_hypotension,
    s.had_tachycardia
  FROM age_matched_icu_full icu
  LEFT JOIN age_matched_instability_score s
    ON icu.stay_id = s.stay_id
)
-- Final output: 95th percentile, top quartile stats, age-matched stats
SELECT
  'ARF ICU Cohort' AS cohort,
  (SELECT p95 FROM percentiles) AS composite_score_95th_percentile,
  -- Top quartile stats
  SUM(CASE WHEN q.quartile = 'top_quartile' THEN 1 ELSE 0 END) AS n_top_quartile,
  AVG(CASE WHEN q.quartile = 'top_quartile' THEN q.los ELSE NULL END) AS mean_los_top_quartile,
  AVG(CASE WHEN q.quartile = 'top_quartile' THEN q.had_hypotension ELSE NULL END) AS pct_hypotension_top_quartile,
  AVG(CASE WHEN q.quartile = 'top_quartile' THEN q.had_tachycardia ELSE NULL END) AS pct_tachycardia_top_quartile,
  AVG(CASE WHEN q.quartile = 'top_quartile' THEN q.hospital_expire_flag ELSE NULL END) AS mortality_top_quartile,
  -- Rest stats
  SUM(CASE WHEN q.quartile = 'rest' THEN 1 ELSE 0 END) AS n_rest,
  AVG(CASE WHEN q.quartile = 'rest' THEN q.los ELSE NULL END) AS mean_los_rest,
  AVG(CASE WHEN q.quartile = 'rest' THEN q.had_hypotension ELSE NULL END) AS pct_hypotension_rest,
  AVG(CASE WHEN q.quartile = 'rest' THEN q.had_tachycardia ELSE NULL END) AS pct_tachycardia_rest,
  AVG(CASE WHEN q.quartile = 'rest' THEN q.hospital_expire_flag ELSE NULL END) AS mortality_rest
FROM arf_icu_scores_quartile q

UNION ALL

SELECT
  'Age-matched ICU Cohort' AS cohort,
  NULL AS composite_score_95th_percentile,
  COUNT(*) AS n_top_quartile,
  AVG(los) AS mean_los_top_quartile,
  AVG(had_hypotension) AS pct_hypotension_top_quartile,
  AVG(had_tachycardia) AS pct_tachycardia_top_quartile,
  AVG(hospital_expire_flag) AS mortality_top_quartile,
  NULL AS n_rest,
  NULL AS mean_los_rest,
  NULL AS pct_hypotension_rest,
  NULL AS pct_tachycardia_rest,
  NULL AS mortality_rest
FROM age_matched_icu_scores;