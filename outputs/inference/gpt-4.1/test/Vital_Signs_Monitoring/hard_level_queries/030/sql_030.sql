WITH
-- 1. Identify acute respiratory failure ICD codes
acute_rf_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND (icd_code LIKE '51881' OR icd_code LIKE '51882' OR icd_code LIKE '518%'))
    OR (icd_version = 10 AND (icd_code LIKE 'J96%' OR icd_code LIKE 'J960%' OR icd_code LIKE 'J961%' OR icd_code LIKE 'J969%'))
),

-- 2. Cohort: Female ICU patients aged 43-53 with acute respiratory failure
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  JOIN acute_rf_icd rf
    ON diag.icd_code = rf.icd_code AND diag.icd_version = rf.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 43 AND 53
),

-- 3. General ICU population (female, age 43-53)
general_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 43 AND 53
),

-- 4. Map itemids for vital signs
vital_itemids AS (
  SELECT
    itemid,
    CASE
      WHEN LOWER(label) LIKE '%mean arterial%' OR LOWER(label) LIKE '%map%' THEN 'MAP'
      WHEN LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr%' THEN 'HR'
      WHEN LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%rr%' THEN 'RR'
      WHEN LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 sat%' THEN 'SpO2'
      WHEN LOWER(label) LIKE '%temperature%' OR LOWER(label) LIKE '%temp%' THEN 'Temp'
      ELSE NULL
    END AS vital_type
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%mean arterial%' OR LOWER(label) LIKE '%map%'
    OR LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr%'
    OR LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%rr%'
    OR LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 sat%'
    OR LOWER(label) LIKE '%temperature%' OR LOWER(label) LIKE '%temp%'
),

-- 5. Extract vital signs in first 48h for cohort
vitals_cohort AS (
  SELECT
    c.stay_id,
    v.vital_type,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN vital_itemids v
    ON ce.itemid = v.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
),

-- 6. Calculate abnormal episodes per stay (vital instability index)
vii_cohort AS (
  SELECT
    stay_id,
    SUM(CASE WHEN vital_type = 'MAP' AND valuenum < 65 THEN 1 ELSE 0 END) AS map_low,
    SUM(CASE WHEN vital_type = 'HR' AND valuenum > 100 THEN 1 ELSE 0 END) AS hr_high,
    SUM(CASE WHEN vital_type = 'RR' AND valuenum > 30 THEN 1 ELSE 0 END) AS rr_high,
    SUM(CASE WHEN vital_type = 'SpO2' AND valuenum < 90 THEN 1 ELSE 0 END) AS spo2_low,
    SUM(CASE WHEN vital_type = 'Temp' AND (valuenum < 36 OR valuenum > 38) THEN 1 ELSE 0 END) AS temp_abn,
    -- VII = sum of all abnormal episodes
    SUM(
      CASE WHEN vital_type = 'MAP' AND valuenum < 65 THEN 1 ELSE 0 END
      + CASE WHEN vital_type = 'HR' AND valuenum > 100 THEN 1 ELSE 0 END
      + CASE WHEN vital_type = 'RR' AND valuenum > 30 THEN 1 ELSE 0 END
      + CASE WHEN vital_type = 'SpO2' AND valuenum < 90 THEN 1 ELSE 0 END
      + CASE WHEN vital_type = 'Temp' AND (valuenum < 36 OR valuenum > 38) THEN 1 ELSE 0 END
    ) AS vii
  FROM vitals_cohort
  GROUP BY stay_id
),

-- 7. Calculate 95th percentile of VII
vii_percentiles AS (
  SELECT
    APPROX_QUANTILES(vii, 100)[OFFSET(95)] AS vii_95th,
    APPROX_QUANTILES(vii, 100)[OFFSET(75)] AS vii_75th
  FROM vii_cohort
),

-- 8. Mark top quartile cohort
top_quartile_cohort AS (
  SELECT
    vc.stay_id,
    vc.map_low,
    vc.hr_high,
    vc.vii
  FROM vii_cohort vc
  CROSS JOIN vii_percentiles vp
  WHERE vc.vii >= vp.vii_75th
),

-- 9. Outcomes for cohort and top quartile
cohort_outcomes AS (
  SELECT
    c.stay_id,
    vc.map_low,
    vc.hr_high,
    c.los,
    CASE
      WHEN adm.hospital_expire_flag = 1 OR pat.dod IS NOT NULL THEN 1 ELSE 0
    END AS mortality
  FROM cohort c
  JOIN vii_cohort vc
    ON c.stay_id = vc.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON c.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON c.subject_id = pat.subject_id
),

top_quartile_outcomes AS (
  SELECT
    c.stay_id,
    vc.map_low,
    vc.hr_high,
    c.los,
    CASE
      WHEN adm.hospital_expire_flag = 1 OR pat.dod IS NOT NULL THEN 1 ELSE 0
    END AS mortality
  FROM cohort c
  JOIN top_quartile_cohort vc
    ON c.stay_id = vc.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON c.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON c.subject_id = pat.subject_id
), -- <--- FIX: Add comma here

-- 10. Outcomes for general ICU population
general_vitals AS (
  SELECT
    g.stay_id,
    v.vital_type,
    ce.charttime,
    ce.valuenum
  FROM general_icu g
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON g.stay_id = ce.stay_id
  JOIN vital_itemids v
    ON ce.itemid = v.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN g.intime AND TIMESTAMP_ADD(g.intime, INTERVAL 48 HOUR)
),

general_vii AS (
  SELECT
    stay_id,
    SUM(CASE WHEN vital_type = 'MAP' AND valuenum < 65 THEN 1 ELSE 0 END) AS map_low,
    SUM(CASE WHEN vital_type = 'HR' AND valuenum > 100 THEN 1 ELSE 0 END) AS hr_high
  FROM general_vitals
  GROUP BY stay_id
),

general_outcomes AS (
  SELECT
    g.stay_id,
    gv.map_low,
    gv.hr_high,
    g.los,
    CASE
      WHEN adm.hospital_expire_flag = 1 OR pat.dod IS NOT NULL THEN 1 ELSE 0
    END AS mortality
  FROM general_icu g
  JOIN general_vii gv
    ON g.stay_id = gv.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON g.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON g.subject_id = pat.subject_id
)

-- Final output
SELECT
  'Cohort (Acute RF, Female 43-53)' AS group,
  (SELECT vii_95th FROM vii_percentiles) AS vii_95th_percentile,
  AVG(map_low) AS avg_map_low_episodes,
  AVG(hr_high) AS avg_tachy_episodes,
  AVG(los) AS avg_icu_los,
  AVG(mortality) AS mortality_rate
FROM cohort_outcomes

UNION ALL

SELECT
  'Top Quartile Cohort' AS group,
  (SELECT vii_95th FROM vii_percentiles) AS vii_95th_percentile,
  AVG(map_low) AS avg_map_low_episodes,
  AVG(hr_high) AS avg_tachy_episodes,
  AVG(los) AS avg_icu_los,
  AVG(mortality) AS mortality_rate
FROM top_quartile_outcomes

UNION ALL

SELECT
  'General ICU Population' AS group,
  NULL AS vii_95th_percentile,
  AVG(map_low) AS avg_map_low_episodes,
  AVG(hr_high) AS avg_tachy_episodes,
  AVG(los) AS avg_icu_los,
  AVG(mortality) AS mortality_rate
FROM general_outcomes;