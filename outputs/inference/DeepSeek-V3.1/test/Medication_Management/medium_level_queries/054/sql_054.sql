WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.icd_code LIKE 'E1%'  -- Diabetes codes (E10-E14)
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.icd_code LIKE 'I50%'  -- Heart failure
    )
    AND a.dischtime IS NOT NULL  -- Ensure we have discharge time
),

glp1_drugs AS (
  -- Common GLP-1 agonists
  SELECT 'semaglutide' AS drug_name UNION ALL
  SELECT 'liraglutide' UNION ALL
  SELECT 'dulaglutide' UNION ALL
  SELECT 'exenatide' UNION ALL
  SELECT 'lixisenatide'
),

-- Check prescriptions (HOSP)
glp1_prescriptions AS (
  SELECT 
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  CROSS JOIN glp1_drugs gd
  WHERE LOWER(pr.drug) LIKE CONCAT('%', gd.drug_name, '%')
),

-- Check inputevents (ICU) for GLP-1 administrations
glp1_inputs AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id, -- Use hadm_id from inputevents for accurate join
    ie.starttime,
    ie.endtime  -- Corrected column name from endtime to endtime
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  CROSS JOIN glp1_drugs gd
  WHERE 
    LOWER(ie.ordercategorydescription) LIKE CONCAT('%', gd.drug_name, '%')
    OR LOWER(ie.ordercomponenttypedescription) LIKE CONCAT('%', gd.drug_name, '%')
),

-- Combine all GLP-1 events (from both HOSP and ICU)
glp1_events AS (
  SELECT subject_id, hadm_id, starttime, endtime FROM glp1_prescriptions
  UNION ALL
  SELECT subject_id, hadm_id, starttime, endtime FROM glp1_inputs
),

-- For each admission, check if GLP-1 was used in first 48h or last 24h
glp1_flags AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
          WHEN ge.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) 
          THEN 1 ELSE 0 
        END) AS glp1_first_48h,
    MAX(CASE 
          WHEN ge.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime 
          THEN 1 ELSE 0 
        END) AS glp1_last_24h
  FROM cohort c
  LEFT JOIN glp1_events ge
    ON c.hadm_id = ge.hadm_id
  GROUP BY c.hadm_id
)

-- Calculate prevalence and net change
SELECT 
  COUNT(*) AS total_admissions,
  ROUND(100.0 * SUM(glp1_first_48h) / COUNT(*), 2) AS prevalence_first_48h,
  ROUND(100.0 * SUM(glp1_last_24h) / COUNT(*), 2) AS prevalence_last_24h,
  ROUND(100.0 * SUM(glp1_last_24h) / COUNT(*), 2) - ROUND(100.0 * SUM(glp1_first_48h) / COUNT(*), 2) AS net_change
FROM glp1_flags;