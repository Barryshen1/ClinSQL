WITH patient_info AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 65 AND 67
),
hf_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Heart failure%' AND d.icd_version = 10
),
creatinine_itemid AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label LIKE '%Creatinine%' AND fluid = 'Blood'
)
SELECT MAX(l.valuenum) AS max_admission_creatinine
FROM patient_info pi
INNER JOIN hf_admissions hfa ON pi.hadm_id = hfa.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON pi.hadm_id = l.hadm_id
WHERE l.itemid IN (SELECT itemid FROM creatinine_itemid)
AND l.charttime BETWEEN pi.admittime AND TIMESTAMP_ADD(pi.admittime, INTERVAL 24 HOUR);