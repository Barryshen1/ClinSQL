WITH male_sepsis_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE pat.gender = 'M'
    AND LOWER(dd.long_title) LIKE '%sepsis%'
),
creatinine_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'blood'
    AND LOWER(category) = 'chemistry'
)
SELECT MAX(le.valuenum) AS max_admission_serum_creatinine
FROM male_sepsis_admissions msa
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  ON msa.subject_id = le.subject_id
  AND msa.hadm_id = le.hadm_id
JOIN creatinine_items ci
  ON le.itemid = ci.itemid
WHERE le.valuenum IS NOT NULL
  AND le.charttime >= msa.admittime
  AND le.charttime < TIMESTAMP_ADD(msa.admittime, INTERVAL 1 DAY);