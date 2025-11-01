WITH cohort AS (
  -- Base cohort: female Medicare patients aged 68-78, ED admission, alive at discharge
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
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1
    AND d.icd_version = 'ICD-10-CM'
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%')
    AND REGEXP_CONTAINS(icd.long_title, r'hemorrhage|hemorrhagic')
    AND a.dischtime IS NOT NULL
),

index_admissions AS (
  -- Identify index admissions (no prior admission within 30 days) and flag 30-day readmissions
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.los_days,
    -- Flag if this is an index admission (no prior adm within 30 days)
    CASE 
      WHEN LAG(c.admittime) OVER (PARTITION BY c.subject_id ORDER BY c.admittime) IS NULL 
        OR DATE_DIFF(c.admittime, LAG(c.dischtime) OVER (PARTITION BY c.subject_id ORDER BY c.admittime), DAY) > 30
      THEN 1 
      ELSE 0 
    END AS is_index,
    -- Flag if this admission has a readmission within 30 days (using LEAD for efficiency)
    CASE 
      WHEN LEAD(c.admittime) OVER (PARTITION BY c.subject_id ORDER BY c.admittime) IS NOT NULL
        AND DATE_DIFF(LEAD(c.admittime) OVER (PARTITION BY c.subject_id ORDER BY c.admittime), c.dischtime, DAY) <= 30
      THEN 1 
      ELSE 0 
    END AS has_readmission
  FROM cohort c
)

-- Final metrics (only index admissions)
SELECT 
  -- 30-day readmission rate
  ROUND(AVG(CASE WHEN has_readmission = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS readmission_rate_percent,
  
  -- Median LOS for readmitted vs non-readmitted
  IFNULL(PERCENTILE_CONT(los_days, 0.5) IGNORE NULLS, 0) OVER (WHERE has_readmission = 1) AS median_los_readmitted_days,
  IFNULL(PERCENTILE_CONT(los_days, 0.5) IGNORE NULLS, 0) OVER (WHERE has_readmission = 0) AS median_los_non_readmitted_days,
  
  -- % with LOS >4 days (overall index admissions)
  ROUND(AVG(CASE WHEN los_days > 4 THEN 1.0 ELSE 0.0 END) * 100, 2) AS percent_los_gt_4_days
FROM index_admissions
WHERE is_index = 1;