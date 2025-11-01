WITH cohort_patients AS (
  -- Define cohort: females 39-49 with primary asthma exacerbation (ICD-10 J45%)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND d.seq_num = 1  -- Primary diagnosis
    AND d.icd_version = '10'  -- ICD-10 for modern codes
    AND d.icd_code LIKE 'J45%'  -- Asthma (exacerbation as primary)
),

all_female_inpatients AS (
  -- All female inpatients for comparison
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
),

lab_scores AS (
  -- Calculate lab instability score: count of distinct abnormal lab types per admission in first 48h
  SELECT 
    le.subject_id,
    le.hadm_id,
    COUNT(DISTINCT le.itemid) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  INNER JOIN cohort_patients cp
    ON le.subject_id = cp.subject_id AND le.hadm_id = cp.hadm_id
  WHERE le.charttime <= TIMESTAMP_ADD(cp.admittime, INTERVAL 48 HOUR)
    AND le.hadm_id IS NOT NULL  -- Inpatient labs
    AND le.valuenum IS NOT NULL
    AND (
      le.flag = 'abnormal'  -- Flagged abnormal
      OR (le.valuenum < le.ref_range_lower AND le.ref_range_lower IS NOT NULL)
      OR (le.valuenum > le.ref_range_upper AND le.ref_range_upper IS NOT NULL)
    )
    AND li.category IN ('Chemistry', 'Hematology', 'Blood Gas', 'Urine')
  GROUP BY le.subject_id, le.hadm_id
),

all_female_lab_scores AS (
  -- Same for all female inpatients
  SELECT 
    le.subject_id,
    le.hadm_id,
    COUNT(DISTINCT le.itemid) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  INNER JOIN all_female_inpatients afi
    ON le.subject_id = afi.subject_id AND le.hadm_id = afi.hadm_id
  WHERE le.charttime <= TIMESTAMP_ADD(afi.admittime, INTERVAL 48 HOUR)
    AND le.hadm_id IS NOT NULL
    AND le.valuenum IS NOT NULL
    AND (
      le.flag = 'abnormal'
      OR (le.valuenum < le.ref_range_lower AND le.ref_range_lower IS NOT NULL)
      OR (le.valuenum > le.ref_range_upper AND le.ref_range_upper IS NOT NULL)
    )
    AND li.category IN ('Chemistry', 'Hematology', 'Blood Gas', 'Urine')
  GROUP BY le.subject_id, le.hadm_id
),

cohort_outcomes AS (
  -- LOS and mortality for cohort
  SELECT 
    COUNT(DISTINCT cp.hadm_id) AS num_admissions,
    AVG(TIMESTAMP_DIFF(COALESCE(cp.dischtime, cp.admittime), cp.admittime, HOUR) / 24.0) AS mean_los_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TIMESTAMP_DIFF(COALESCE(cp.dischtime, cp.admittime), cp.admittime, HOUR) / 24.0) OVER () AS median_los_days,
    SUM(CAST(cp.hospital_expire_flag AS INT64)) * 100.0 / COUNT(DISTINCT cp.hadm_id) AS mortality_rate_pct,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY COALESCE(ls.lab_instability_score, 0)) OVER () AS p75_lab_score,
    AVG(COALESCE(ls.lab_instability_score, 0)) AS mean_lab_score
  FROM cohort_patients cp
  LEFT JOIN lab_scores ls ON cp.hadm_id = ls.hadm_id
),

all_outcomes AS (
  -- Same for all female inpatients
  SELECT 
    COUNT(DISTINCT afi.hadm_id) AS num_admissions,
    AVG(TIMESTAMP_DIFF(COALESCE(afi.dischtime, afi.admittime), afi.admittime, HOUR) / 24.0) AS mean_los_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TIMESTAMP_DIFF(COALESCE(afi.dischtime, afi.admittime), afi.admittime, HOUR) / 24.0) OVER () AS median_los_days,
    SUM(CAST(afi.hospital_expire_flag AS INT64)) * 100.0 / COUNT(DISTINCT afi.hadm_id) AS mortality_rate_pct,
    AVG(COALESCE(afs.lab_instability_score, 0)) AS mean_lab_score,
    NULL AS p75_lab_score  -- Not computed for all cohort
  FROM all_female_inpatients afi
  LEFT JOIN all_female_lab_scores afs ON afi.hadm_id = afs.hadm_id
)

-- Combine results
SELECT 'Cohort' AS group_type, num_admissions, mean_los_days, median_los_days, mortality_rate_pct, p75_lab_score, mean_lab_score
FROM cohort_outcomes
UNION ALL
SELECT 'All Female Inpatients' AS group_type, num_admissions, mean_los_days, median_los_days, mortality_rate_pct, p75_lab_score, mean_lab_score
FROM all_outcomes;