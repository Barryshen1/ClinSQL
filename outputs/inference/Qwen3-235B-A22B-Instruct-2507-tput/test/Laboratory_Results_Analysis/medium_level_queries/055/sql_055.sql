WITH patient_admissions AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 81 AND 91
),

-- Filter admissions with chest pain or AMI (ICD-10 codes)
admissions_with_diagnosis AS (
  SELECT DISTINCT pa.hadm_id
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
    AND (
      d.icd_code LIKE 'I21%'  -- AMI codes
      OR d.icd_code = 'R07.9' -- Chest pain, unspecified
    )
),

-- Get first (index) hs-TnT value per admission
troponin_values AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  WHERE dl.label = 'Troponin T' -- Assuming this is hs-TnT; itemid 50341 in MIMIC-IV
    AND le.valuenum IS NOT NULL
),

index_troponin AS (
  SELECT hadm_id, valuenum
  FROM troponin_values
  WHERE rn = 1
),

-- Combine with diagnosis and classify troponin
classified_troponin AS (
  SELECT 
    it.hadm_id,
    it.valuenum,
    CASE
      WHEN it.valuenum < 14 THEN 'Normal'
      WHEN it.valuenum BETWEEN 14 AND 59 THEN 'Borderline'
      WHEN it.valuenum >= 60 THEN 'Myocardial injury'
      ELSE 'Unknown'
    END AS troponin_category
  FROM index_troponin it
  INNER JOIN admissions_with_diagnosis ad ON it.hadm_id = ad.hadm_id
),

-- Add LOS from admissions
los_data AS (
  SELECT 
    a.hadm_id,
    c.troponin_category,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN classified_troponin c ON a.hadm_id = c.hadm_id
)

-- Final aggregation
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM los_data
GROUP BY troponin_category
ORDER BY troponin_category;