WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
hf_patients AS (
  SELECT DISTINCT fa.*
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON fa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE dd.icd_code LIKE 'I50%'
    AND dd.icd_version = 10
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q25,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q75
FROM hf_patients
WHERE los_days IS NOT NULL AND los_days >= 0;