WITH hf_admissions AS (
  SELECT 
      admissions.subject_id, 
      admissions.hadm_id, 
      admissions.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
      ON admissions.subject_id = patients.subject_id
  WHERE 
      patients.gender = 'M'
      AND patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year) = 66
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
          WHERE 
              diag.hadm_id = admissions.hadm_id
              AND (
                  (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
                  OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
              )
      )
)
SELECT 
    MAX(le.valuenum) AS max_creatinine
FROM hf_admissions AS ha
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON ha.hadm_id = le.hadm_id
WHERE 
    le.itemid = 50912  -- Serum Creatinine
    AND le.charttime BETWEEN ha.admittime AND DATETIME_ADD(ha.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL;