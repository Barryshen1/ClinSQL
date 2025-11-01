WITH patient_admissions AS (
  SELECT p.subject_id, a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
),
tia_diagnoses AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Transient ischemic attack%' AND di.icd_version = 10
),
imaging_procedures AS (
  SELECT h.hadm_id, COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON h.hcpcs_cd = dh.code
  WHERE CAST(dh.category AS STRING) LIKE '%Diagnostic Imaging%' 
  GROUP BY h.hadm_id
)
SELECT 
  CASE 
    WHEN pa.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN pa.los BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_category,
  COUNT(pa.hadm_id) AS num_admissions,
  AVG(ip.num_procedures) AS mean_procedures,
  MIN(ip.num_procedures) AS min_procedures,
  MAX(ip.num_procedures) AS max_procedures
FROM patient_admissions pa
JOIN tia_diagnoses td ON pa.hadm_id = td.hadm_id
JOIN imaging_procedures ip ON pa.hadm_id = ip.hadm_id
WHERE pa.los BETWEEN 1 AND 7
GROUP BY los_category
ORDER BY los_category;