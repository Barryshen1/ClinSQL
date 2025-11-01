WITH admissions_with_age AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    adm.admission_location,
    adm.insurance,
    EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
),
principal_hf AS (
  SELECT
    di.subject_id,
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '428%') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
)
SELECT
  COUNT(DISTINCT a.hadm_id) AS num_index_admissions
FROM admissions_with_age AS a
JOIN principal_hf AS hf
  ON a.subject_id = hf.subject_id
  AND a.hadm_id = hf.hadm_id
WHERE a.gender = 'F'
  AND a.age_at_admit BETWEEN 65 AND 75
  AND a.insurance = 'Medicare'
  AND UPPER(a.admission_location) LIKE '%TRANSFER%HOSPITAL%'
;