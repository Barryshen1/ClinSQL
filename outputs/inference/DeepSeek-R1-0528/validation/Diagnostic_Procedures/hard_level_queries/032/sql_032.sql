WITH base_cohort AS (
  SELECT 
    icu.subject_id, 
    icu.hadm_id, 
    icu.stay_id, 
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age,
    icu.intime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  -- Filter for first ICU stay per patient
  WHERE icu.stay_id = (
    SELECT MIN(stay_id)
    FROM `physionet-data.mimiciv_3_1_icu.icustays` 
    WHERE subject_id = icu.subject_id
  )
),
sepsis_flag AS (
  SELECT 
    base.hadm_id,
    MAX(
      CASE WHEN 
        (diag.icd_version = 9 AND diag.icd_code IN ('038', '785.52', '995.91', '995.92'))
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'A4%' OR diag.icd_code LIKE 'R65.2%' OR diag.icd_code = 'R57.2')
      THEN 1 ELSE 0 END
    ) AS sepsis
  FROM base_cohort base
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON base.hadm_id = diag.hadm_id
  GROUP BY base.hadm_id
),
sepsis_procedures AS (
  SELECT 
    base.stay_id,
    COUNT(DISTINCT proc.itemid) AS proc_count
  FROM base_cohort base
  INNER JOIN sepsis_flag sf 
    ON base.hadm_id = sf.hadm_id AND sf.sepsis = 1
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON base.stay_id = proc.stay_id
    AND proc.starttime BETWEEN base.intime AND DATETIME_ADD(base.intime, INTERVAL 48 HOUR)
  GROUP BY base.stay_id
),
sepsis_90th AS (
  SELECT 
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS proc_90th_percentile
  FROM sepsis_procedures
),
cohort_data AS (
  SELECT 
    base.*,
    CASE WHEN sf.sepsis = 1 THEN 'sepsis' ELSE 'control' END AS cohort,
    DATE_DIFF(base.dischtime, base.admittime, DAY) AS los
  FROM base_cohort base
  LEFT JOIN sepsis_flag sf 
    ON base.hadm_id = sf.hadm_id
  WHERE 
    base.gender = 'F'
    AND base.age BETWEEN 66 AND 76
    -- Ensure control group has no sepsis
    AND (sf.sepsis = 1 OR sf.sepsis = 0) 
),
aggregated AS (
  SELECT 
    cohort,
    COUNT(*) AS num_patients,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS los_median,
    APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_q1,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS los_q3,
    SUM(hospital_expire_flag) AS mortality_count,
    AVG(hospital_expire_flag) AS mortality_rate,
    (SELECT proc_90th_percentile FROM sepsis_90th) AS proc_90th_percentile
  FROM cohort_data
  GROUP BY cohort
)
SELECT 
  cohort,
  num_patients,
  los_median,
  los_q1,
  los_q3,
  mortality_count,
  ROUND(mortality_rate * 100, 2) AS mortality_rate_percent,
  CASE 
    WHEN cohort = 'sepsis' THEN proc_90th_percentile 
    ELSE NULL 
  END AS proc_90th_percentile
FROM aggregated;