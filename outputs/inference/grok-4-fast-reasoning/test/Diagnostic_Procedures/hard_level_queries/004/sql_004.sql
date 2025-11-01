WITH ich_hadms AS (
  -- Subquery: Hospital admissions (hadm_id) for female subjects aged 50-60 with ICH diagnosis
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON di.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      (di.icd_version = 9 AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%'))
      OR (
        di.icd_version = 10
        AND (
          di.icd_code LIKE 'I60%'
          OR di.icd_code LIKE 'I61%'
          OR di.icd_code LIKE 'I62%'
        )
      )
    )
),
cohort_stays AS (
  -- Qualifying ICU stays for the cohort
  SELECT i.stay_id, i.subject_id, i.hadm_id, i.intime, i.los, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  INNER JOIN ich_hadms ih ON i.hadm_id = ih.hadm_id
),
proc_cohort AS (
  -- Procedure counts for cohort stays (first 72 hours)
  SELECT cs.stay_id, COUNT(*) AS procedure_count
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = cs.stay_id
    AND pe.starttime >= cs.intime
    AND pe.starttime < cs.intime + INTERVAL 72 HOUR
  GROUP BY cs.stay_id
),
general_stats AS (
  -- Aggregates for all ICU stays (general)
  SELECT
    PERCENTILE_CONT(i.los, 0.5) AS median_los,
    COUNT(DISTINCT CASE WHEN a.hospital_expire_flag = 1 THEN i.hadm_id END) * 1.0 / COUNT(DISTINCT i.hadm_id) AS mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
cohort_stats AS (
  SELECT
    PERCENTILE_CONT(COALESCE(pc.procedure_count, 0), 0.25) AS cohort_25th_procedure_burden,
    PERCENTILE_CONT(COALESCE(pc.procedure_count, 0), 0.5) AS cohort_median_procedure_burden,
    PERCENTILE_CONT(COALESCE(pc.procedure_count, 0), 0.9) AS cohort_90th_procedure_burden,
    PERCENTILE_CONT(cs.los, 0.5) AS cohort_median_los_days,
    COUNT(DISTINCT CASE WHEN cs.hospital_expire_flag = 1 THEN cs.hadm_id END) * 1.0 / COUNT(DISTINCT cs.hadm_id) AS cohort_mortality_rate
  FROM cohort_stays cs
  LEFT JOIN proc_cohort pc ON cs.stay_id = pc.stay_id
)
SELECT
  cs.cohort_25th_procedure_burden,
  cs.cohort_median_procedure_burden,
  cs.cohort_90th_procedure_burden,
  cs.cohort_median_los_days,
  cs.cohort_mortality_rate,
  gs.median_los AS general_median_los_days,
  gs.mortality_rate AS general_mortality_rate
FROM cohort_stats cs
CROSS JOIN general_stats gs;