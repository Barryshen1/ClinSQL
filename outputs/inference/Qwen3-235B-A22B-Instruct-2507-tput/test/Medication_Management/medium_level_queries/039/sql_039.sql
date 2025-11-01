WITH cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  -- T2DM diagnosis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d1
    ON a.hadm_id = d1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dc1
    ON d1.icd_code = dc1.icd_code AND d1.icd_version = dc1.icd_version
  -- Heart failure diagnosis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d2
    ON a.hadm_id = d2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dc2
    ON d2.icd_code = dc2.icd_code AND d2.icd_version = dc2.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND dc1.long_title LIKE '%diabetes mellitus type 2%'
    AND dc1.icd_code LIKE 'E11%'
    AND dc2.long_title LIKE '%heart failure%'
    AND dc2.icd_code LIKE 'I50%'
),
glp1_use AS (
  SELECT DISTINCT
    c.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_ADD(a.admittime, INTERVAL 24 HOUR) AS first_24h_end,
    DATETIME_SUB(a.dischtime, INTERVAL 48 HOUR) AS final_48h_start,
    -- Check if any GLP-1 given in first 24h
    MAX(CASE 
      WHEN pr.starttime >= a.admittime 
       AND pr.starttime < DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
       THEN 1 ELSE 0 END) AS received_first_24h,
    -- Check if any GLP-1 given in final 48h
    MAX(CASE 
      WHEN pr.starttime >= DATETIME_SUB(a.dischtime, INTERVAL 48 HOUR)
       AND pr.starttime <= a.dischtime
       THEN 1 ELSE 0 END) AS received_final_48h
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON c.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON a.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) IN ('liraglutide', 'semaglutide', 'exenatide', 'dulaglutide', 'lixisenatide')
    AND LOWER(pr.route) LIKE '%subcut%'
    AND pr.starttime IS NOT NULL
    AND a.dischtime IS NOT NULL
  GROUP BY c.subject_id, a.hadm_id, a.admittime, a.dischtime
),
summary AS (
  SELECT
    COUNT(*) AS total_patients,
    AVG(received_first_24h) * 100 AS pct_first_24h,
    AVG(received_final_48h) * 100 AS pct_final_48h
  FROM glp1_use
)
SELECT
  pct_first_24h,
  pct_final_48h,
  ROUND(pct_final_48h - pct_first_24h, 2) AS absolute_change,
  ROUND(
    CASE 
      WHEN pct_first_24h > 0 
      THEN (pct_final_48h - pct_first_24h) / pct_first_24h * 100 
      ELSE NULL 
    END, 2) AS relative_change_percent
FROM summary;