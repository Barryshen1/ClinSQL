SELECT MAX(le.valuenum) AS max_peak_creatinine_mg_dl
FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON le.hadm_id = a.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON a.hadm_id = di.hadm_id
WHERE p.gender = 'F'
  AND le.itemid = 50912
  AND le.valuenum IS NOT NULL
  AND le.valueuom = 'mg/dL'
  AND le.charttime >= a.admittime
  AND le.charttime <= a.dischtime
  AND (
    (di.icd_version = 9 
     AND (di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code = '496'))
    OR
    (di.icd_version = 10 AND di.icd_code LIKE 'J44%')
  );