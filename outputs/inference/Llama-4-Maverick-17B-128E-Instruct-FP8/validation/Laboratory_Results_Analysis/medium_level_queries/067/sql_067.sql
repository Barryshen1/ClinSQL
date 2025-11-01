WITH ami_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Myocardial infarction%' AND d.icd_version = 10
),
first_troponin AS (
  SELECT l.hadm_id, MIN(l.valuenum) AS first_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label LIKE '%Troponin T%' AND l.valuenum > 0.01
  GROUP BY l.hadm_id
),
patient_info AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.hospital_expire_flag, 
         (DATE(a.dischtime) - DATE(a.admittime)) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 52 AND 62
  AND a.hadm_id IN (SELECT hadm_id FROM ami_admissions)
),
filtered_patients AS (
  SELECT pi.subject_id, pi.hadm_id, pi.anchor_age, pi.los, pi.hospital_expire_flag, ft.first_troponin
  FROM patient_info pi
  INNER JOIN first_troponin ft ON pi.hadm_id = ft.hadm_id
)
SELECT 
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(anchor_age) AS mean_age,
  AVG(los) AS mean_los,
  MIN(first_troponin) AS min_first_troponin,
  MAX(first_troponin) AS max_first_troponin,
  AVG(first_troponin) AS avg_first_troponin,
  SUM(hospital_expire_flag) / COUNT(hadm_id) AS in_hospital_mortality
FROM filtered_patients;