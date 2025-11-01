WITH copd_patients AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 9 AND d.icd_code = '496'
     OR (di.icd_version = 10 AND d.icd_code LIKE 'J44%')
),
female_copd AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN copd_patients c ON p.subject_id = c.subject_id
  WHERE p.gender = 'F'
),
creatinine_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%' 
    AND LOWER(fluid) = 'blood'
),
patient_max_creat AS (
  SELECT 
    le.subject_id,
    MAX(le.valuenum) AS max_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN creatinine_items ci ON le.itemid = ci.itemid
  INNER JOIN female_copd fc ON le.subject_id = fc.subject_id
  WHERE le.valuenum IS NOT NULL
  GROUP BY le.subject_id
)
SELECT MAX(max_creatinine) AS max_peak_serum_creatinine
FROM patient_max_creat;