WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.anchor_age BETWEEN 68 AND 78
    AND p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND d.seq_num = 1
    AND d.icd_code LIKE 'N39%'
    AND a.hospital_expire_flag = 0
    AND icd.long_title LIKE '%urinary tract infection%'
),
indexed_cohort AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM cohort
  WHERE rn = 1
),
readmissions AS (
  SELECT 
    *,
    CASE 
      WHEN next_admittime IS NOT NULL 
           AND DATE_DIFF(next_admittime, dischtime, DAY) <= 30 
      THEN 1 
      ELSE 0 
    END AS readmit_flag
  FROM indexed_cohort
)
SELECT 
  -- 30-day readmission rate
  AVG(readmit_flag) * 100 AS readmission_rate_pct,
  
  -- Overall % stays >6 days
  AVG(CASE WHEN los_days > 6 THEN 1.0 ELSE 0 END) * 100 AS pct_stays_over_6_days,
  
  -- Median LOS for readmitted
  PERCENTILE_CONT(los_days ORDER BY los_days) 
    IGNORE NULLS 
    WITHIN GROUP (ORDER BY CASE WHEN readmit_flag = 1 THEN 1 ELSE 0 END) AS median_los_readmitted,
  
  -- Median LOS for non-readmitted
  PERCENTILE_CONT(los_days ORDER BY los_days) 
    IGNORE NULLS 
    WITHIN GROUP (ORDER BY CASE WHEN readmit_flag = 0 THEN 1 ELSE 0 END) AS median_los_non_readmitted
  
FROM readmissions;