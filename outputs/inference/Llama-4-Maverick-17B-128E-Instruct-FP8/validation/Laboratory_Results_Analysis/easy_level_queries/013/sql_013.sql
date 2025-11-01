WITH copd_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND dicd.long_title LIKE '%Chronic obstructive pulmonary disease%'
),
creatinine_lab AS (
  SELECT l.subject_id, l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label = 'Creatinine' AND dl.fluid = 'Blood'
)
SELECT MAX(cl.valuenum) AS max_creatinine
FROM copd_patients cp
INNER JOIN creatinine_lab cl ON cp.subject_id = cl.subject_id;