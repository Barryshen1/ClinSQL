WITH
-- 1. Get status epilepticus ICD codes
status_epilepticus_icds AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%status epilepticus%'
),

-- 2. Get all ICU stays for female patients aged 63-73
icu_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
),

-- 3. Identify status epilepticus ICU stays
se_icu_stays AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
  FROM icu_patients icu
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON icu.subject_id = d.subject_id AND icu.hadm_id = d.hadm_id
  JOIN status_epilepticus_icds s
    ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
),

-- 4. Get vital signs for first 72h for both cohorts
vitals AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    i.intime,
    i.outtime,
    -- HR
    CASE WHEN c.itemid IN (220045, 211) THEN c.valuenum ELSE NULL END AS hr,
    -- MAP
    CASE WHEN c.itemid IN (220181, 51) THEN c.valuenum ELSE NULL END AS map,
    -- SpO2
    CASE WHEN c.itemid IN (220277, 646) THEN c.valuenum ELSE NULL END AS spo2,
    -- RR
    CASE WHEN c.itemid IN (220210, 618) THEN c.valuenum ELSE NULL END AS rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_patients i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE c.itemid IN (220045, 211, 220181, 51, 220277, 646, 220210, 618)
    AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
),

-- 5. Pivot vital signs per timepoint
vitals_pivot AS (
  SELECT
    subject_id, hadm_id, stay_id, charttime,
    MAX(hr) AS hr,
    MAX(map) AS map,
    MAX(spo2) AS spo2,
    MAX(rr) AS rr
  FROM vitals
  GROUP BY subject_id, hadm_id, stay_id, charttime
),

-- 6. Compute instability index and flags per timepoint
vitals_index AS (
  SELECT
    subject_id, hadm_id, stay_id, charttime,
    -- Flags
    CASE WHEN hr > 120 THEN 1 ELSE 0 END AS tachycardia,
    CASE WHEN map < 65 THEN 1 ELSE 0 END AS hypotension,
    CASE WHEN spo2 < 90 THEN 1 ELSE 0 END AS hypoxemia,
    CASE WHEN rr > 30 THEN 1 ELSE 0 END AS tachypnea,
    -- Composite index
    (CASE WHEN hr > 120 THEN 1 ELSE 0 END
     + CASE WHEN map < 65 THEN 1 ELSE 0 END
     + CASE WHEN spo2 < 90 THEN 1 ELSE 0 END
     + CASE WHEN rr > 30 THEN 1 ELSE 0 END) AS vital_instability_index
  FROM vitals_pivot
),

-- 7. Aggregate per ICU stay
icu_metrics AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    COUNT(*) AS n_timepoints,
    AVG(v.vital_instability_index) AS mean_vital_instability_index,
    APPROX_QUANTILES(v.vital_instability_index, 100)[OFFSET(25)] AS p25_vital_instability_index,
    APPROX_QUANTILES(v.vital_instability_index, 100)[OFFSET(50)] AS p50_vital_instability_index,
    APPROX_QUANTILES(v.vital_instability_index, 100)[OFFSET(75)] AS p75_vital_instability_index,
    APPROX_QUANTILES(v.vital_instability_index, 100)[OFFSET(90)] AS p90_vital_instability_index,
    SUM(v.tachycardia) / COUNT(*) AS tachycardia_burden,
    SUM(v.hypotension) / COUNT(*) AS map_lt_65_burden
  FROM vitals_index v
  GROUP BY v.subject_id, v.hadm_id, v.stay_id
),

-- 8. Add LOS and mortality
icu_metrics_full AS (
  SELECT
    m.*,
    i.los,
    a.hospital_expire_flag
  FROM icu_metrics m
  JOIN icu_patients i
    ON m.subject_id = i.subject_id AND m.hadm_id = i.hadm_id AND m.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON m.subject_id = a.subject_id AND m.hadm_id = a.hadm_id
),

-- 9. Status epilepticus cohort
se_metrics AS (
  SELECT m.*
  FROM icu_metrics_full m
  JOIN se_icu_stays s
    ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id AND m.stay_id = s.stay_id
),

-- 10. General ICU cohort (female, age 63-73, all diagnoses)
gen_metrics AS (
  SELECT m.*
  FROM icu_metrics_full m
  LEFT JOIN se_icu_stays s
    ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id AND m.stay_id = s.stay_id
  WHERE s.subject_id IS NULL
)

-- 11. Final output: summary statistics for both cohorts
SELECT
  'Status Epilepticus' AS cohort,
  COUNT(*) AS n_stays,
  ROUND(AVG(mean_vital_instability_index),2) AS mean_vital_instability_index,
  ROUND(APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(25)],2) AS p25_vital_instability_index,
  ROUND(APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(50)],2) AS p50_vital_instability_index,
  ROUND(APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(75)],2) AS p75_vital_instability_index,
  ROUND(APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(90)],2) AS p90_vital_instability_index,
  ROUND(AVG(tachycardia_burden),3) AS mean_tachycardia_burden,
  ROUND(AVG(map_lt_65_burden),3) AS mean_map_lt_65_burden,
  ROUND(AVG(los),2) AS mean_icu_los,
  ROUND(SUM(CASE WHEN hospital_expire_flag=1 THEN 1 ELSE 0 END)/COUNT(*),3) AS mortality_rate
FROM se_metrics

UNION ALL

SELECT
  'General ICU' AS cohort,
  COUNT(*) AS n_stays,
  ROUND(AVG(mean_vital_instability_index),2) AS mean_vital_instability_index,
  ROUND(APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(25)],2) AS p25_vital_instability_index,
  ROUND(APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(50)],2) AS p50_vital_instability_index,
  ROUND(APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(75)],2) AS p75_vital_instability_index,
  ROUND(APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(90)],2) AS p90_vital_instability_index,
  ROUND(AVG(tachycardia_burden),3) AS mean_tachycardia_burden,
  ROUND(AVG(map_lt_65_burden),3) AS mean_map_lt_65_burden,
  ROUND(AVG(los),2) AS mean_icu_los,
  ROUND(SUM(CASE WHEN hospital_expire_flag=1 THEN 1 ELSE 0 END)/COUNT(*),3) AS mortality_rate
FROM gen_metrics;