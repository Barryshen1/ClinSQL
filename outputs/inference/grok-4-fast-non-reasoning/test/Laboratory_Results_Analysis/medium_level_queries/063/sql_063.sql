WITH acs_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id
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
    ON d.icd_code = icd.icd_code 
    AND CAST(d.icd_version AS STRING) = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.seq_num = 1
    AND (d.icd_version = 10 OR d.icd_version = 9)
    AND (
      -- ICD-10 ACS codes
      (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      OR
      -- ICD-9 ACS codes
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR d.icd_code LIKE '413%'))
    )
    AND (icd.long_title LIKE '%angina%' OR icd.long_title LIKE '%infarction%')
),
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS troponin_value
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  INNER JOIN 
    acs_admissions aa
    ON le.hadm_id = aa.hadm_id
  WHERE 
    (li.label LIKE '%TroponinI%' OR li.label LIKE '%TROPONIN I%')
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0.04  -- 99th percentile ULN for Troponin I (ng/mL)
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT 
  COUNT(*) AS patient_count,
  AVG(troponin_value) AS mean_troponin,
  PERCENTILE_CONT(troponin_value, 0.5) OVER() AS median_troponin,
  PERCENTILE_CONT(troponin_value, 0.25) OVER() AS q1_troponin,
  PERCENTILE_CONT(troponin_value, 0.75) OVER() AS q3_troponin,
  PERCENTILE_CONT(troponin_value, 0.75) OVER() - PERCENTILE_CONT(troponin_value, 0.25) OVER() AS iqr_troponin
FROM 
  first_troponin;