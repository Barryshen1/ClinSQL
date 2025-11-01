WITH
-- Identify admissions that have any diagnosis whose description contains 'heart failure'
hf_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),

-- Base admissions joined to patients, and mark heart failure admissions
base_adm AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    IF(hf.hadm_id IS NOT NULL, TRUE, FALSE) AS heart_failure,
    -- LOS in seconds for later conversion to days
    TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), SECOND) AS los_seconds
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  LEFT JOIN hf_hadm hf
    USING(hadm_id)
  -- exclude admissions missing admit/discharge times (ongoing) so LOS is defined
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Count distinct critically abnormal lab item types per admission within first 72 hours
lab_crit_counts AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT le.itemid) AS crit_lab_types
  FROM base_adm a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = a.hadm_id
   -- ensure comparisons are between TIMESTAMPs
   AND TIMESTAMP(le.charttime) BETWEEN TIMESTAMP(a.admittime) AND TIMESTAMP_ADD(TIMESTAMP(a.admittime), INTERVAL 72 HOUR)
   -- require numeric value and both reference bounds for reliable comparison
   AND le.valuenum IS NOT NULL
   AND le.ref_range_lower IS NOT NULL
   AND le.ref_range_upper IS NOT NULL
   AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY a.hadm_id
),

-- Combine admissions with their lab-critical counts (0 if none)
adm_with_counts AS (
  SELECT
    a.*,
    COALESCE(l.crit_lab_types, 0) AS crit_lab_types
  FROM base_adm a
  LEFT JOIN lab_crit_counts l
    USING(hadm_id)
)

-- Final aggregated results for two cohorts: HF male age 37-47, and all inpatients
SELECT
  cohort,
  admissions_n,
  max_lab_instability,
  ROUND(100 * critical_event_rate, 2) AS critical_event_rate_pct,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(median_los_days, 2) AS median_los_days,
  ROUND(100 * mortality_rate, 2) AS mortality_rate_pct
FROM (
  -- Heart failure cohort: male, age 37-47, with heart failure diagnosis
  SELECT
    'HF_male_age_37_47' AS cohort,
    COUNT(*) AS admissions_n,
    MAX(crit_lab_types) AS max_lab_instability,
    SAFE_DIVIDE(SUM(CASE WHEN crit_lab_types >= 1 THEN 1 ELSE 0 END), COUNT(*)) AS critical_event_rate,
    SAFE_DIVIDE(AVG(los_seconds), 86400) AS mean_los_days,
    APPROX_QUANTILE(SAFE_DIVIDE(los_seconds, 86400), 0.5) AS median_los_days,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate
  FROM adm_with_counts
  WHERE gender = 'M'
    AND anchor_age BETWEEN 37 AND 47
    AND heart_failure = TRUE

  UNION ALL

  -- General inpatients: all admissions (completed) in the dataset
  SELECT
    'All_inpatients' AS cohort,
    COUNT(*) AS admissions_n,
    MAX(crit_lab_types) AS max_lab_instability,
    SAFE_DIVIDE(SUM(CASE WHEN crit_lab_types >= 1 THEN 1 ELSE 0 END), COUNT(*)) AS critical_event_rate,
    SAFE_DIVIDE(AVG(los_seconds), 86400) AS mean_los_days,
    APPROX_QUANTILE(SAFE_DIVIDE(los_seconds, 86400), 0.5) AS median_los_days,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate
  FROM adm_with_counts
)
ORDER BY cohort;