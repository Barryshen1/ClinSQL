WITH cabg_procedures AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE icd_version = 9 AND long_title LIKE '%Coronary artery bypass%' 
     OR icd_version = 10 AND long_title LIKE '%Coronary artery bypass%'
),
cabg_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON a.hadm_id = proc.hadm_id AND a.subject_id = proc.subject_id
  WHERE proc.icd_code IN (SELECT icd_code FROM cabg_procedures)
),
patient_age_gender AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 74 AND 84
),
first_cabg_admission AS (
  SELECT ca.subject_id, MIN(ca.hadm_id) AS hadm_id
  FROM cabg_admissions ca
  INNER JOIN patient_age_gender pag ON ca.subject_id = pag.subject_id
  GROUP BY ca.subject_id
),
icu_los AS (
  SELECT AVG(DATE_DIFF(i.outtime, i.intime, DAY)) AS mean_icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN first_cabg_admission fca ON i.hadm_id = fca.hadm_id
)
SELECT mean_icu_los
FROM icu_los;