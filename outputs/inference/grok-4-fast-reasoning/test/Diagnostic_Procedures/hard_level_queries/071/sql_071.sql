WITH patients_elig AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 50 AND 60
),
first_icu AS (
  SELECT subject_id, stay_id, hadm_id, intime,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  JOIN patients_elig USING (subject_id)
  WHERE first_careunit NOT IN ('Discharge', 'Regular Floor')
  QUALIFY rn = 1
),
all_first_icu AS (
  SELECT subject_id, stay_id, hadm_id, intime,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE first_careunit NOT IN ('Discharge', 'Regular Floor')
  QUALIFY rn = 1
),
ich_cohort AS (
  SELECT f.subject_id, f.stay_id, f.hadm_id, f.intime
  FROM first_icu f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON f.hadm_id = d.hadm_id
  WHERE d.icd_version = 10 AND d.icd_code LIKE 'I61%'
),
general_los_mort AS (
  SELECT 
    'General ICU' AS cohort,
    COUNT(*) AS n_patients,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS avg_hosp_los_days,
    AVG(a.hospital_expire_flag) AS in_hosp_mortality_rate
  FROM all_first_icu f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.hadm_id = a.hadm_id
  WHERE a.dischtime > a.admittime  -- Ensure valid LOS
),
ich_los_mort_base AS (
  SELECT 
    ic.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    a.hospital_expire_flag AS died
  FROM ich_cohort ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ic.hadm_id = a.hadm_id
  WHERE a.dischtime > a.admittime
),
ich_procedure_counts AS (
  SELECT 
    ic.subject_id,
    COUNT(p.itemid) AS proc_count  -- Total procedure events in first 72h
  FROM ich_cohort ic
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p 
    ON p.stay_id = ic.stay_id
    AND p.starttime >= ic.intime
    AND p.starttime < TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
    AND p.starttime IS NOT NULL  -- Valid start times only
  GROUP BY ic.subject_id
),
ich_los_mort AS (
  SELECT 
    'ICH Cohort' AS cohort,
    COUNT(*) AS n_patients,
    AVG(los_days) AS avg_hosp_los_days,
    AVG(died) AS in_hosp_mortality_rate
  FROM ich_los_mort_base
),
ich_procedures AS (
  SELECT 
    'ICH Cohort' AS cohort,
    PERCENTILE_CONT(COALESCE(proc_count, 0), 0.25) OVER () AS p25_proc_count,
    PERCENTILE_CONT(COALESCE(proc_count, 0), 0.50) OVER () AS p50_proc_count,
    PERCENTILE_CONT(COALESCE(proc_count, 0), 0.90) OVER () AS p90_proc_count,
    MAX(COALESCE(proc_count, 0)) OVER () AS max_proc_count
  FROM ich_procedure_counts
)
-- Combine all stats (LOS/mortality for both; procedures for ICH only)
SELECT 
  cohort,
  n_patients,
  ROUND(avg_hosp_los_days, 2) AS avg_hosp_los_days,
  ROUND(in_hosp_mortality_rate, 4) AS in_hosp_mortality_rate,
  NULL AS p25_proc_count,
  NULL AS p50_proc_count,
  NULL AS p90_proc_count,
  NULL AS max_proc_count
FROM general_los_mort
UNION ALL
SELECT 
  il.cohort,
  il.n_patients,
  ROUND(il.avg_hosp_los_days, 2),
  ROUND(il.in_hosp_mortality_rate, 4),
  ROUND(ip.p25_proc_count, 0),
  ROUND(ip.p50_proc_count, 0),
  ROUND(ip.p90_proc_count, 0),
  ip.max_proc_count
FROM ich_los_mort il
JOIN ich_procedures ip ON il.cohort = ip.cohort
ORDER BY cohort;