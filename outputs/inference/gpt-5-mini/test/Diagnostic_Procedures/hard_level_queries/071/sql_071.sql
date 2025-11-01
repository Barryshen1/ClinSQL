WITH ich_hadm AS (
  -- admissions with an ICH diagnosis (text-based match on d_icd_diagnoses.long_title)
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%hemorrhag%'
    AND (
      LOWER(dd.long_title) LIKE '%intracranial%' 
      OR LOWER(dd.long_title) LIKE '%intracerebral%' 
      OR LOWER(dd.long_title) LIKE '%subarachnoid%' 
      OR LOWER(dd.long_title) LIKE '%subdural%'
    )
),

-- Per-ICU-stay counts of procedureevents occurring in the first 72 hours after ICU intime
icu_proc_counts AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    -- count procedureevents for this stay that occur within 72 hours of icu.intime
    SUM(
      CASE
        WHEN COALESCE(pe.starttime, pe.endtime) IS NOT NULL
         AND COALESCE(pe.starttime, pe.endtime) BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
        THEN 1
        ELSE 0
      END
    ) AS proc_count,
    -- hospital LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 1440.0) AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = icu.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = icu.hadm_id
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, a.dischtime, a.admittime, a.hospital_expire_flag
)

-- Metrics for the ICH female 50-60 cohort and for the general ICU population
SELECT
  cohort,
  -- Procedure burden percentiles and max (first 72 hours)
  proc_p25,
  proc_p50,
  proc_p90,
  proc_max,
  -- Hospital LOS (days): median (approx), mean
  los_median_days,
  ROUND(los_mean_days, 2) AS los_mean_days,
  -- In-hospital mortality proportion
  ROUND(mortality_rate, 4) AS mortality_rate,
  n_stays
FROM (
  -- ICH female age 50-60 cohort
  SELECT
    'ICH_female_50_60' AS cohort,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS proc_p25,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(50)] AS proc_p50,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS proc_p90,
    MAX(proc_count) AS proc_max,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_median_days,
    AVG(los_days) AS los_mean_days,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate,
    COUNT(*) AS n_stays
  FROM icu_proc_counts ipc
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ipc.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND ipc.hadm_id IN (SELECT hadm_id FROM ich_hadm)

  UNION ALL

  -- General ICU population (all ICU stays)
  SELECT
    'General_ICU' AS cohort,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS proc_p25,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(50)] AS proc_p50,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS proc_p90,
    MAX(proc_count) AS proc_max,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_median_days,
    AVG(los_days) AS los_mean_days,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate,
    COUNT(*) AS n_stays
  FROM icu_proc_counts ipc
)
ORDER BY cohort;