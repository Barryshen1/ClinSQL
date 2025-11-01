WITH hf_admissions AS (
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = 10
    AND REGEXP_CONTAINS(dd.icd_code, '^I50')
),
copd_admissions AS (
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = 10
    AND REGEXP_CONTAINS(dd.icd_code, '^J44')
),
target_admissions AS (
  SELECT hf.hadm_id
  FROM hf_admissions hf
  INNER JOIN copd_admissions copd
    ON hf.hadm_id = copd.hadm_id
),
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN target_admissions ta
    ON a.hadm_id = ta.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
)

SELECT STDDEV_SAMP(los_days) AS los_sd_days
FROM eligible_patients;