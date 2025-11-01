WITH icu_stays_filtered AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.los AS icu_los,
    a.hospital_expire_flag,
    DATETIME_ADD(ie.intime, INTERVAL 72 HOUR) AS time_72h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ie.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),
-- Get COPD exacerbation status per admission
copd_dx AS (
  SELECT DISTINCT
    di.hadm_id,
    TRUE AS has_copd_exacerbation
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code = 'J441' AND d.icd_version = 10
),
-- For each ICU stay, count distinct procedures in first 72h
procedure_counts AS (
  SELECT 
    ie.stay_id,
    COUNT(DISTINCT ie.itemid) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` ie
  INNER JOIN icu_stays_filtered s
    ON ie.stay_id = s.stay_id
  WHERE ie.starttime >= s.intime 
    AND ie.starttime <= s.time_72h
    AND ie.statusdescription = 'completed'
  GROUP BY ie.stay_id
),
-- Combine ICU stays with COPD status and procedure counts
cohort AS (
  SELECT 
    s.subject_id,
    s.stay_id,
    s.hadm_id,
    s.icu_los,
    s.hospital_expire_flag,
    COALESCE(cd.has_copd_exacerbation, FALSE) AS has_copd_exacerbation,
    COALESCE(pc.distinct_procedure_count, 0) AS distinct_procedure_count
  FROM icu_stays_filtered s
  LEFT JOIN copd_dx cd ON s.hadm_id = cd.hadm_id
  LEFT JOIN procedure_counts pc ON s.stay_id = pc.stay_id
)
-- Final aggregation: 75th percentile for COPD group, and compare outcomes
SELECT
  APPROX_QUANTILES(CASE WHEN has_copd_exacerbation THEN distinct_procedure_count END, 100)[OFFSET(75)] AS copd_75th_percentile_distinct_procedures,
  AVG(CASE WHEN has_copd_exacerbation THEN icu_los END) AS copd_mean_icu_los,
  AVG(CASE WHEN has_copd_exacerbation THEN hospital_expire_flag END) AS copd_in_hospital_mortality,
  AVG(CASE WHEN NOT has_copd_exacerbation THEN icu_los END) AS non_copd_mean_icu_los,
  AVG(CASE WHEN NOT has_copd_exacerbation THEN hospital_expire_flag END) AS non_copd_in_hospital_mortality
FROM cohort;