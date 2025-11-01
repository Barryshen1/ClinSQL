WITH intracranial_hadm AS (
  -- admissions (hadm_id) that have at least one diagnosis suggesting intracranial hemorrhage
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%hemorrhag%' -- contains "hemorrhage"/"hemorrhagic" etc.
    AND (
      LOWER(dd.long_title) LIKE '%intracran%'   -- intracranial
      OR LOWER(dd.long_title) LIKE '%cerebr%'   -- cerebral / cerebr...
      OR LOWER(dd.long_title) LIKE '%subarach%' -- subarachnoid
      OR LOWER(dd.long_title) LIKE '%subdural%' -- subdural
      OR LOWER(dd.long_title) LIKE '%epidural%'  -- epidural
    )
),

icu_proc_counts AS (
  -- Count procedureevents within first 72 hours of each ICU stay
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    COALESCE(COUNT(pe.starttime), 0) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = s.stay_id
   AND pe.starttime IS NOT NULL
   AND pe.starttime >= s.intime
   AND pe.starttime <= TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  GROUP BY s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime, s.los, p.gender, p.anchor_age, a.hospital_expire_flag
),

-- Cohort stays: female, age 50-60, and admission has intracranial hemorrhage
cohort_stays AS (
  SELECT ipc.*
  FROM icu_proc_counts ipc
  WHERE ipc.gender = 'F'
    AND ipc.anchor_age BETWEEN 50 AND 60
    AND ipc.hadm_id IN (SELECT hadm_id FROM intracranial_hadm)
),

-- General ICU stays (all ICU stays)
general_stays AS (
  SELECT ipc.*
  FROM icu_proc_counts ipc
)

-- Final aggregation: percentiles for procedure burden (cohort) and comparison of ICU LOS and mortality
SELECT
  'Female 50-60 with intracranial hemorrhage' AS group_label,
  COUNT(*) AS n_stays,
  -- Procedure burden percentiles (approximate) computed from the cohort_stays CTE via scalar subqueries
  (SELECT APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] FROM cohort_stays) AS proc_p25,
  (SELECT APPROX_QUANTILES(proc_count, 100)[OFFSET(50)] FROM cohort_stays) AS proc_median,
  (SELECT APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] FROM cohort_stays) AS proc_p90,
  -- ICU LOS median (approximate)
  (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM cohort_stays) AS los_median_days,
  -- In-hospital mortality proportion
  SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS hospital_mortality
FROM cohort_stays

UNION ALL

SELECT
  'General ICU (all stays)' AS group_label,
  COUNT(*) AS n_stays,
  CAST(NULL AS FLOAT64) AS proc_p25,
  CAST(NULL AS FLOAT64) AS proc_median,
  CAST(NULL AS FLOAT64) AS proc_p90,
  (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM general_stays) AS los_median_days,
  SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS hospital_mortality
FROM general_stays
;