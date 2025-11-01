WITH relevant_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
),
sepsis_patients AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%sepsis%'
)
SELECT 
  STDDEV(DATETIME_DIFF(i.outtime, i.intime, DAY)) AS stddev_los
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
INNER JOIN relevant_patients rp ON i.subject_id = rp.subject_id
INNER JOIN sepsis_patients sp ON i.subject_id = sp.subject_id AND i.hadm_id = sp.hadm_id;