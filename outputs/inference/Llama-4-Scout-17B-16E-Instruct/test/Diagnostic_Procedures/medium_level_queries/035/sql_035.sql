WITH 
  -- Identify AKI patients
  aki_patients AS (
    SELECT DISTINCT 
      le.subject_id, 
      le.hadm_id,
      CASE 
        WHEN le.valuenum > 1.5 AND le.valuenum > (SELECT MAX(valuenum) FROM `physionet-data.mimiciv_3_1_hosp.labevents` WHERE subject_id = le.subject_id AND itemid = 220050 AND charttime < le.charttime ORDER BY charttime DESC LIMIT 1) * 1.5 
          THEN 1 
        ELSE 0 
      END AS aki_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE 
      le.itemid = 220050  -- Creatinine
      AND le.valuenum IS NOT NULL
  ),
  
  -- Classify AKI as primary or secondary
  aki_classification AS (
    SELECT 
      ap.subject_id,
      ap.hadm_id,
      CASE 
        WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
          WHERE pi.hadm_id = ap.hadm_id 
          AND pi.icd_code LIKE '92%'  -- e.g., surgeries, procedures
        ) THEN 'Secondary'
        ELSE 'Primary'
      END AS aki_type
    FROM 
      aki_patients ap
    WHERE 
      ap.aki_flag = 1
  ),
  
  -- Patient demographics and admission LOS
  patient_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      TIMESTAMPDIFF(DAY, a.admittime, a.dischtime) AS los,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
  ),
  
  -- MRI/CT counts
  imaging_counts AS (
    SELECT 
      hadm_id,
      COUNT(*) AS imaging_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE 
      hcpcs_cd IN ('70544', '74160', '74170', '72148', '72158', '72159')  -- Example HCPCS codes for MRI/CT
    GROUP BY 
      hadm_id
  )

SELECT 
  CASE 
    WHEN pa.los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN pa.los BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_category,
  ac.aki_type,
  COUNT(DISTINCT pa.hadm_id) AS patient_count,
  AVG(ii.imaging_count) AS mean_imaging_count
FROM 
  patient_admissions pa
JOIN 
  aki_classification ac 
    ON pa.subject_id = ac.subject_id AND pa.hadm_id = ac.hadm_id
LEFT JOIN 
  imaging_counts ii 
    ON pa.hadm_id = ii.hadm_id
WHERE 
  pa.anchor_age BETWEEN 43 AND 53
  AND pa.gender = 'M'
GROUP BY 
  los_category, 
  ac.aki_type
ORDER BY 
  los_category, 
  ac.aki_type;