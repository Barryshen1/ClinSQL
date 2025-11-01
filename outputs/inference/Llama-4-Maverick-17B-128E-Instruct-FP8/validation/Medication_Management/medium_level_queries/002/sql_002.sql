WITH 
diabetes_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Type 2 diabetes mellitus%' OR diag.icd_code LIKE 'E11%'
),
heart_failure_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%heart failure%' 
  OR diag.icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%heart failure%')
),
eligible_patients AS (
  SELECT pat.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pat.subject_id = adm.subject_id
  WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 59 AND 69
  AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 48
  AND adm.hadm_id IN (SELECT hadm_id FROM diabetes_patients)
  AND adm.hadm_id IN (SELECT hadm_id FROM heart_failure_patients)
),
glp1_use AS (
  SELECT DISTINCT ep.hadm_id, 
         CASE 
           WHEN presc.starttime BETWEEN ep.admittime AND DATETIME_ADD(ep.admittime, INTERVAL 48 HOUR) THEN 1 
           ELSE 0 
         END AS glp1_first_48h,
         CASE 
           WHEN presc.starttime BETWEEN DATETIME_SUB(ep.dischtime, INTERVAL 12 HOUR) AND ep.dischtime THEN 1 
           ELSE 0 
         END AS glp1_last_12h
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` presc
  JOIN eligible_patients ep ON presc.hadm_id = ep.hadm_id
  WHERE LOWER(presc.drug) LIKE '%liraglutide%' OR LOWER(presc.drug) LIKE '%semaglutide%' 
  OR LOWER(presc.drug) LIKE '%exenatide%' OR LOWER(presc.drug) LIKE '%dulaglutide%' 
  OR LOWER(presc.drug) LIKE '%albiglutide%' 
),
prevalence AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN glp1_first_48h = 1 THEN hadm_id END) AS count_glp1_first_48h,
    COUNT(DISTINCT hadm_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN glp1_last_12h = 1 THEN hadm_id END) AS count_glp1_last_12h
  FROM glp1_use
)
SELECT 
  count_glp1_first_48h / total_patients AS prevalence_first_48h,
  count_glp1_last_12h / total_patients AS prevalence_last_12h,
  (count_glp1_last_12h / total_patients) - (count_glp1_first_48h / total_patients) AS absolute_difference
FROM prevalence;