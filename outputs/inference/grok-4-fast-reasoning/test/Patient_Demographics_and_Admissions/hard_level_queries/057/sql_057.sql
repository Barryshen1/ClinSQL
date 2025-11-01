WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.subject_id = di.subject_id 
    AND a.hadm_id = di.hadm_id 
    AND di.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddd 
    ON di.icd_code = ddd.icd_code 
    AND di.icd_version = ddd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND LOWER(ddd.long_title) LIKE '%urinary tract infection%'
),
flagged AS (
  SELECT 
    *,
    (SELECT COUNT(*) > 0 
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` a 
     WHERE a.subject_id = cohort.subject_id 
       AND a.hadm_id != cohort.hadm_id 
       AND a.admittime > cohort.dischtime 
       AND a.admittime <= TIMESTAMP_ADD(cohort.dischtime, INTERVAL 30 DAY)
    ) AS is_readmitted
  FROM cohort
),
totals AS (
  SELECT 
    COUNT(*) AS total_admissions,
    COUNT(CASE WHEN is_readmitted THEN 1 END) AS readmitted_count,
    COUNT(CASE WHEN los > 9 THEN 1 END) AS long_los_count
  FROM flagged
),
median_readmitted AS (
  SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
  FROM flagged 
  WHERE is_readmitted
),
median_non_readmitted AS (
  SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
  FROM flagged 
  WHERE NOT is_readmitted
)
SELECT 
  (t.readmitted_count * 100.0 / t.total_admissions) AS readmission_rate_pct,
  mr.median_los AS median_los_readmitted,
  mn.median_los AS median_los_non_readmitted,
  (t.long_los_count * 100.0 / t.total_admissions) AS pct_los_gt_9
FROM totals t
CROSS JOIN median_readmitted mr
CROSS JOIN median_non_readmitted mn;