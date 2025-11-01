WITH index_cohort AS (
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
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.anchor_age BETWEEN 83 AND 93
    AND p.gender = 'M'
    AND a.insurance LIKE '%MEDICARE%'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
    AND d.seq_num = 1
    AND d.icd_code = 'G45.9'
    AND d.icd_version = '10'
    AND EXTRACT(YEAR FROM a.admittime) >= 2008
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1  -- First qualifying admission per patient
),
readmissions AS (
  SELECT 
    ic.subject_id,
    ic.hadm_id AS index_hadm_id,
    ic.admittime AS index_admittime,
    ic.dischtime AS index_dischtime,
    ic.los_days AS index_los_days,
    ra.hadm_id AS readmit_hadm_id,
    ra.admittime AS readmit_admittime
  FROM 
    index_cohort ic
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` ra
    ON ic.subject_id = ra.subject_id
    AND ra.hadm_id != ic.hadm_id  -- Exclude same admission
    AND ra.admittime > ic.dischtime  -- After index discharge
    AND ra.admittime <= TIMESTAMP_ADD(ic.dischtime, INTERVAL 30 DAY)
    AND ra.hospital_expire_flag = 0  -- Exclude readmit deaths for consistency
    AND ra.insurance LIKE '%MEDICARE%'  -- Ensure readmit also Medicare
),
readmitted AS (
  SELECT DISTINCT subject_id, index_los_days
  FROM readmissions
  WHERE readmit_hadm_id IS NOT NULL
),
non_readmitted AS (
  SELECT ic.subject_id, ic.index_los_days
  FROM index_cohort ic
  LEFT JOIN (
    SELECT DISTINCT subject_id
    FROM readmissions
    WHERE readmit_hadm_id IS NOT NULL
  ) r ON ic.subject_id = r.subject_id
  WHERE r.subject_id IS NULL
)
SELECT 
  COUNT(DISTINCT CASE WHEN r.readmit_hadm_id IS NOT NULL THEN r.subject_id END) / COUNT(DISTINCT ic.subject_id) * 100 AS readmission_rate_pct,
  
  -- Median index LOS for readmitted
  PERCENTILE_CONT(rd.index_los_days, 0.5) OVER() AS median_los_readmitted_days,
  
  -- Median index LOS for non-readmitted
  PERCENTILE_CONT(nr.index_los_days, 0.5) OVER() AS median_los_non_readmitted_days,
  
  -- Percent of index stays >10 days
  COUNTIF(ic.los_days > 10) / COUNT(*) * 100 AS pct_index_stays_gt_10_days

FROM index_cohort ic
LEFT JOIN readmissions r ON ic.subject_id = r.subject_id
LEFT JOIN readmitted rd ON ic.subject_id = rd.subject_id
LEFT JOIN non_readmitted nr ON ic.subject_id = nr.subject_id;