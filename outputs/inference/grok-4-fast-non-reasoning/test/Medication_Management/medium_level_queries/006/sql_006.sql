WITH cohort AS (
  -- Base cohort: females 48-58 with T2DM and HF diagnoses
  SELECT DISTINCT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.hospital_expire_flag = 0  -- Inpatients discharged alive
    AND a.admittime < a.dischtime  -- Valid admission
    AND d.icd_version = '10'  -- ICD-10 for recency
    AND (
      -- T2DM: any E11 code
      d.icd_code LIKE 'E11%' OR
      -- HF: any I50 code
      d.icd_code LIKE 'I50%'
    )
  GROUP BY a.hadm_id, a.admittime, a.dischtime
  HAVING COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'E11%' THEN d.icd_code END) > 0  -- Has T2DM
     AND COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'I50%' THEN d.icd_code END) > 0  -- Has HF
),

first_72h_initiations AS (
  -- Admissions with GLP-1 initiation in first 72h
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 3 DAY)  -- First 72h
    AND (
      LOWER(pr.drug) LIKE '%semaglutide%' OR
      LOWER(pr.drug) LIKE '%liraglutide%' OR
      LOWER(pr.drug) LIKE '%dulaglutide%' OR
      LOWER(pr.drug) LIKE '%exenatide%' OR
      LOWER(pr.drug) LIKE '%tirzepatide%'
    )
    AND pr.drug_type = 'MAIN'  -- Focus on primary orders
),

last_48h_initiations AS (
  -- Admissions with GLP-1 initiation in last 48h (only if los >= 2 days)
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 2 DAY)
    AND pr.starttime < c.dischtime  -- Last 48h
    AND (
      LOWER(pr.drug) LIKE '%semaglutide%' OR
      LOWER(pr.drug) LIKE '%liraglutide%' OR
      LOWER(pr.drug) LIKE '%dulaglutide%' OR
      LOWER(pr.drug) LIKE '%exenatide%' OR
      LOWER(pr.drug) LIKE '%tirzepatide%'
    )
    AND pr.drug_type = 'MAIN'
    AND DATE_DIFF(c.dischtime, c.admittime, DAY) >= 2  -- Valid window (LOS >= 2 days)
)

-- Final aggregation
SELECT 
  COUNT(DISTINCT c.hadm_id) AS total_admissions,
  COUNT(DISTINCT f.hadm_id) AS first_72h_initiations_n,
  SAFE_DIVIDE(COUNT(DISTINCT f.hadm_id), COUNT(DISTINCT c.hadm_id)) * 100 AS first_72h_rate_pct,
  COUNT(DISTINCT l.hadm_id) AS last_48h_initiations_n,
  SAFE_DIVIDE(COUNT(DISTINCT l.hadm_id), COUNT(DISTINCT c.hadm_id)) * 100 AS last_48h_rate_pct,
  ABS(
    SAFE_DIVIDE(COUNT(DISTINCT f.hadm_id), COUNT(DISTINCT c.hadm_id)) * 100 -
    SAFE_DIVIDE(COUNT(DISTINCT l.hadm_id), COUNT(DISTINCT c.hadm_id)) * 100
  ) AS absolute_difference_pp
FROM cohort c
LEFT JOIN first_72h_initiations f ON c.hadm_id = f.hadm_id
LEFT JOIN last_48h_initiations l ON c.hadm_id = l.hadm_id;