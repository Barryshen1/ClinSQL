WITH cohort AS (
  -- Base cohort: first admission per patient meeting criteria
  SELECT 
    a.subject_id,
    a.hadm_id AS index_hadm_id,
    a.admittime AS index_admittime,
    a.dischtime AS index_dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS index_los,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.insurance = 'Medicare'
    AND a.admission_location LIKE '%ED%'
    AND a.hospital_expire_flag = 0  -- Exclude deaths
    AND d.seq_num = '1'  -- Principal diagnosis
    AND (
      -- UTI ICD codes (ICD-9 and ICD-10)
      (d.icd_version = '9' AND d.icd_code = '5990') OR
      (d.icd_version = '10' AND d.icd_code LIKE 'N3%')
    )
),

readmissions AS (
  -- Flag 30-day readmissions
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` next_a
        WHERE next_a.subject_id = c.subject_id
          AND next_a.hadm_id != c.index_hadm_id
          AND next_a.admittime <= DATE_ADD(c.index_dischtime, INTERVAL 30 DAY)
          AND next_a.hospital_expire_flag = 0  -- Optional: exclude readmits ending in death
      ) THEN 1 ELSE 0 
    END AS readmitted
  FROM cohort c
  WHERE c.rn = 1  -- First admission only
)

-- Final metrics
SELECT 
  readmitted,
  -- Readmission rate (overall, repeated for each group)
  SAFE_DIVIDE(SUM(readmitted), (SELECT COUNT(*) FROM readmissions)) * 100.0 AS readmission_rate_pct,
  
  -- Median LOS by readmitted status
  PERCENTILE_CONT(index_los, 0.5) OVER (PARTITION BY readmitted) AS median_los,
  
  -- Percent LOS > 9 days by readmitted status
  SAFE_DIVIDE(
    SUM(CASE WHEN index_los > 9 THEN 1 ELSE 0 END), 
    COUNT(*)
  ) * 100.0 AS pct_los_gt_9
FROM readmissions
GROUP BY readmitted
ORDER BY readmitted;