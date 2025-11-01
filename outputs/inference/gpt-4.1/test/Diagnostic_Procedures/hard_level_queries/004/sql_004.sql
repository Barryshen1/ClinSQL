WITH
-- 1. Identify ICU stays for females aged 50-60
icu_patients AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
),

-- 2. Identify admissions with intracranial hemorrhage (ICD-9: 431, 432.x; ICD-10: I61.x, I62.x)
ich_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      (d.icd_version = 9 AND (d.icd_code = '431' OR d.icd_code LIKE '432%'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
),

-- 3. Target cohort: female ICU patients aged 50-60 with ICH
target_cohort AS (
  SELECT
    icu.*
  FROM
    icu_patients icu
    JOIN ich_admissions ich
      ON icu.subject_id = ich.subject_id AND icu.hadm_id = ich.hadm_id
  WHERE
    icu.gender = 'F'
    AND icu.anchor_age BETWEEN 50 AND 60
),

-- 4. Procedure burden for all ICU stays (first 72h)
icu_procedure_burden AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    icu.los,
    -- Count unique ICU procedures in first 72h
    COUNT(DISTINCT proc.itemid) AS icu_proc_count,
    -- Count unique hospital procedures in first 72h
    COUNT(DISTINCT hosp.icd_code) AS hosp_proc_count
  FROM
    icu_patients icu
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
      ON proc.stay_id = icu.stay_id
      AND proc.starttime >= icu.intime
      AND proc.starttime < DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` hosp
      ON hosp.hadm_id = icu.hadm_id
      AND hosp.chartdate >= DATE(icu.intime)
      AND hosp.chartdate < DATE_ADD(DATE(icu.intime), INTERVAL 3 DAY)
  GROUP BY
    icu.stay_id, icu.subject_id, icu.hadm_id, icu.intime, icu.outtime, icu.los
),

-- 5. Merge with mortality
icu_burden_mortality AS (
  SELECT
    b.*,
    a.hospital_expire_flag
  FROM
    icu_procedure_burden b
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON b.hadm_id = a.hadm_id
),

-- 6. Add cohort labels
labeled_burden AS (
  SELECT
    'Target: Female 50-60 ICH' AS cohort,
    b.*
  FROM
    icu_burden_mortality b
    JOIN target_cohort t
      ON b.stay_id = t.stay_id

  UNION ALL

  SELECT
    'General ICU' AS cohort,
    b.*
  FROM
    icu_burden_mortality b
)

-- 7. Final aggregation
SELECT
  cohort,
  COUNT(*) AS n_patients,
  APPROX_QUANTILES(IFNULL(icu_proc_count,0) + IFNULL(hosp_proc_count,0), 100)[SAFE_OFFSET(25)] AS procedure_burden_p25,
  APPROX_QUANTILES(IFNULL(icu_proc_count,0) + IFNULL(hosp_proc_count,0), 2)[SAFE_OFFSET(1)] AS procedure_burden_p50,
  APPROX_QUANTILES(IFNULL(icu_proc_count,0) + IFNULL(hosp_proc_count,0), 100)[SAFE_OFFSET(90)] AS procedure_burden_p90,
  AVG(los) AS mean_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hosp_mortality_rate
FROM
  labeled_burden
GROUP BY
  cohort
ORDER BY
  cohort;