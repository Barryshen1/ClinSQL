WITH patient_selection AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 86 AND 96
),
admissions_with_diagnoses AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         EXTRACT(DATE FROM a.dischtime) - EXTRACT(DATE FROM a.admittime) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = a.hadm_id AND d.icd_code IN ('5780', '5781', '5789', 'K920', 'K921', 'K922')  -- UGIB codes
  ) AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = a.hadm_id AND d.icd_code IN ('49121', 'J441')  -- COPD exacerbation codes
  )
)
SELECT AVG(awd.los_days) AS avg_los
FROM admissions_with_diagnoses awd
JOIN patient_selection ps ON awd.subject_id = ps.subject_id;