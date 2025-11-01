WITH pneumonia_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%pneumonia%'
),
copd_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%chronic obstructive pulmonary disease%'
     OR LOWER(d_icd.long_title) LIKE '%copd%'
     OR LOWER(d_icd.long_title) LIKE '%emphysema%'
     OR LOWER(d_icd.long_title) LIKE '%chronic bronchitis%'
),
eligible_admissions AS (
  SELECT a.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN pneumonia_admissions pa
    ON a.hadm_id = pa.hadm_id
  JOIN copd_admissions ca
    ON a.hadm_id = ca.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT PERCENTILE_CONT(los_days, 0.75) OVER () AS p75_los_days
FROM eligible_admissions
LIMIT 1;