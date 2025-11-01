WITH hf_adms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ((icd_version = 9 AND icd_code LIKE '428%') OR (icd_version = 10 AND icd_code LIKE 'I50%'))
),
copd_adms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ((icd_version = 9 AND (icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '496%')) 
         OR (icd_version = 10 AND icd_code LIKE 'J44%'))
),
both_adms AS (
  SELECT h.subject_id, h.hadm_id
  FROM hf_adms h
  INNER JOIN copd_adms c ON h.subject_id = c.subject_id AND h.hadm_id = c.hadm_id
),
filtered_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN both_adms b ON a.subject_id = b.subject_id AND a.hadm_id = b.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
)
SELECT STDDEV(los_days) AS sd_los_days
FROM filtered_admissions;