WITH index_admissions AS (
  -- Qualifying index admissions
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = '0'
    AND a.dischtime IS NOT NULL
    AND d.seq_num = 1
    AND d.icd_code LIKE 'K92.2%'
    AND d.icd_version = '10'  -- ICD-10 for modern codes
    -- Ensure no prior admission in last 30 days (index only)
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` prev
      WHERE prev.subject_id = a.subject_id
      AND prev.hadm_id != a.hadm_id
      AND prev.dischtime <= a.admittime
      AND DATE_DIFF(a.admittime, prev.dischtime, DAY) <= 30
    )
  -- Dedup to one index per patient (earliest)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

readmissions AS (
  -- Flag readmission within 30 days using EXISTS
  SELECT 
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.los_days,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` ra
        WHERE ra.subject_id = ia.subject_id
        AND ra.hadm_id != ia.hadm_id
        AND ra.admittime > ia.dischtime
        AND DATE_DIFF(ra.admittime, ia.dischtime, DAY) <= 30
        AND ra.hospital_expire_flag = '0'
      ) THEN 1 
      ELSE 0 
    END AS readmitted
  FROM index_admissions ia
)

-- Final metrics
SELECT 
  COUNT(*) AS total_patients,
  COUNTIF(readmitted = 1) AS num_readmitted,
  SAFE_DIVIDE(COUNTIF(readmitted = 1), COUNT(*)) * 100 AS readmission_rate_percent,
  -- Median LOS for readmitted vs not (using APPROX_QUANTILES)
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM readmissions WHERE readmitted = 1) AS median_los_readmitted,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM readmissions WHERE readmitted = 0) AS median_los_not_readmitted,
  -- Overall % with LOS > 6 days
  SAFE_DIVIDE(COUNTIF(los_days > 6), COUNT(*)) * 100 AS percent_los_gt_6_days
FROM readmissions
;