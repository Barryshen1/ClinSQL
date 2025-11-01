WITH first_stays AS (
  -- First ICU stays for all patients
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    pat.gender,
    pat.anchor_age,
    adm.dischtime,
    adm.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE icu.intime IS NOT NULL AND adm.dischtime IS NOT NULL
),
ards_cohort AS (
  -- ARDS filter: ICD codes for ARDS
  SELECT 
    fs.*,
    1 AS cohort_type  -- 1 = ARDS
  FROM first_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON fs.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code 
    AND diag.icd_version = d_icd.icd_version
  WHERE fs.rn = 1
    AND fs.gender = 'F'
    AND fs.anchor_age BETWEEN 37 AND 47
    AND (diag.icd_code = 'J80' 
         OR diag.icd_code = '518.5'  -- ICD-9 ARDS
         OR LOWER(d_icd.long_title) LIKE '%acute respiratory distress syndrome%'  -- Case-insensitive fuzzy match
        )
),
all_cohort AS (
  -- All first stays (same demographic for fair comparison)
  SELECT 
    *,
    0 AS cohort_type  -- 0 = All
  FROM first_stays
  WHERE rn = 1
    AND gender = 'F'
    AND anchor_age BETWEEN 37 AND 47
),
combined_cohort AS (
  SELECT * FROM ards_cohort
  UNION ALL
  SELECT * FROM all_cohort
),
los_calc AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, intime, DAY) AS hospital_los_days
  FROM combined_cohort
),
proc_count AS (
  -- Distinct diagnostic procedures in first 72h (filter to Imaging category for diagnostics)
  SELECT 
    lc.subject_id,
    lc.stay_id,
    lc.cohort_type,
    lc.hospital_los_days,
    lc.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS num_distinct_procs
  FROM los_calc lc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON lc.subject_id = pe.subject_id
    AND lc.hadm_id = pe.hadm_id
    AND lc.stay_id = pe.stay_id
    AND pe.starttime >= lc.intime
    AND pe.starttime <= TIMESTAMP_ADD(lc.intime, INTERVAL 72 HOUR)
    AND pe.itemid IN (
      SELECT itemid 
      FROM `physionet-data.mimiciv_3_1_icu.d_items` 
      WHERE category = 'Imaging'
    )
  GROUP BY lc.subject_id, lc.stay_id, lc.cohort_type, lc.hospital_los_days, lc.hospital_expire_flag
),
cohort_metrics AS (
  SELECT 
    cohort_type,
    MIN(num_distinct_procs) AS min_diagnostic_utilization,
    PERCENTILE_CONT(num_distinct_procs, 0.75) OVER (PARTITION BY cohort_type) AS p75_procs,
    PERCENTILE_CONT(num_distinct_procs, 0.90) OVER (PARTITION BY cohort_type) AS p90_procs,
    PERCENTILE_CONT(hospital_los_days, 0.75) OVER (PARTITION BY cohort_type) AS p75_los,
    PERCENTILE_CONT(hospital_los_days, 0.90) OVER (PARTITION BY cohort_type) AS p90_los,
    AVG(hospital_los_days) OVER (PARTITION BY cohort_type) AS mean_los,
    AVG(hospital_expire_flag * 1.0) OVER (PARTITION BY cohort_type) AS mortality_rate
  FROM proc_count pc
)
SELECT 
  CASE 
    WHEN cohort_type = 1 THEN 'ARDS (Female 37-47, First Stay)'
    ELSE 'All ICU (Female 37-47, First Stay)'
  END AS cohort,
  min_diagnostic_utilization,
  ROUND(p75_procs, 0) AS p75_distinct_procs,
  ROUND(p90_procs, 0) AS p90_distinct_procs,
  ROUND(p75_los, 2) AS p75_hospital_los_days,
  ROUND(p90_los, 2) AS p90_hospital_los_days,
  ROUND(mean_los, 2) AS mean_hospital_los_days,
  ROUND(mortality_rate * 100, 2) AS in_hospital_mortality_pct,
  COUNT(DISTINCT subject_id) AS cohort_size
FROM cohort_metrics
GROUP BY cohort_type, min_diagnostic_utilization, p75_procs, p90_procs, p75_los, p90_los, mean_los, mortality_rate
ORDER BY cohort_type DESC;