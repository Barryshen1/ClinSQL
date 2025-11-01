WITH icu_base AS (
  -- ICU stays joined to patient demographics and admission-level mortality flag
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.gender,
    p.anchor_age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
),
copd_hadm AS (
  -- Admissions that have a diagnosis matching COPD exacerbation (lookup by diagnosis text)
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%copd%'
    AND LOWER(dicd.long_title) LIKE '%exacerb%'
),
proc_counts AS (
  -- Count distinct procedure itemids per ICU stay within the first 72 hours after ICU intime
  SELECT
    pe.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pe.stay_id = icu.stay_id
  WHERE pe.starttime IS NOT NULL
    AND pe.starttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY pe.stay_id
),
icu_cohort AS (
  -- Combine ICU base info, COPD flag and procedure counts; restrict to male, age 88-98
  SELECT
    ib.*,
    CASE WHEN ch.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS copd_exacerbation,
    COALESCE(pc.proc_count, 0) AS proc_count
  FROM icu_base ib
  LEFT JOIN copd_hadm ch
    ON ib.hadm_id = ch.hadm_id
  LEFT JOIN proc_counts pc
    ON ib.stay_id = pc.stay_id
  WHERE ib.gender = 'M'
    AND ib.anchor_age BETWEEN 88 AND 98
)

-- Aggregate results for COPD cohort and the age-matched comparator
SELECT
  'COPD_exacerbation' AS cohort,
  COUNT(*) AS n_stays,
  -- 75th percentile (approx) of distinct procedures in first 72 hours
  APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS p75_distinct_procedures_first_72h,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate
FROM icu_cohort
WHERE copd_exacerbation = 1

UNION ALL

SELECT
  'Age_matched_all' AS cohort,
  COUNT(*) AS n_stays,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS p75_distinct_procedures_first_72h,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate
FROM icu_cohort;