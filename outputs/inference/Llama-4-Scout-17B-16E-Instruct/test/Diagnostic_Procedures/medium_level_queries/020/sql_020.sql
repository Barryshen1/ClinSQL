WITH 
-- Identify TIA patients
tia_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 72 AND 82
  AND dd.long_title LIKE '%Transient ischemic attack%'
),

-- Calculate LOS and ICU use
patient_stays AS (
  SELECT 
    tp.subject_id, tp.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    COUNT(DISTINCT i.stay_id) > 0 AS icu_use
  FROM tia_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON tp.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON tp.hadm_id = i.hadm_id
  GROUP BY tp.subject_id, tp.hadm_id, a.dischtime, a.admittime
),

-- Categorize LOS and count diagnostic imaging procedures
imaging_procedures AS (
  SELECT 
    ps.hadm_id,
    CASE 
      WHEN ps.hospital_los BETWEEN 1 AND 3 THEN '1-3'
      WHEN ps.hospital_los BETWEEN 4 AND 7 THEN '4-7'
      ELSE 'Outside range'
    END AS los_category,
    ps.icu_use,
    COUNT(DISTINCT pi.icd_code) AS num_imaging_procedures
  FROM patient_stays ps
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON ps.hadm_id = pi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE dip.long_title LIKE '%imaging%'  
  GROUP BY ps.hadm_id, ps.icu_use, los_category
)

-- Final aggregation
SELECT 
  los_category,
  icu_use,
  COUNT(DISTINCT hadm_id) AS admission_counts,
  AVG(num_imaging_procedures) AS mean_imaging_procedures
FROM imaging_procedures
GROUP BY los_category, icu_use;