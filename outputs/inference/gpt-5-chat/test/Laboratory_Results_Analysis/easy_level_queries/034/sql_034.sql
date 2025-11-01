WITH heart_failure_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 65
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
    )
),
sodium_labitems AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%sodium%'
    AND LOWER(fluid) = 'blood'
)
SELECT MIN(le.valuenum) AS min_sodium_value
FROM heart_failure_admissions hfa
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON hfa.hadm_id = le.hadm_id
JOIN sodium_labitems sli
  ON le.itemid = sli.itemid
WHERE le.valuenum IS NOT NULL;