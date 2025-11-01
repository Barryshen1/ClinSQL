WITH first_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
)
, pneumonia_first_admissions AS (
  SELECT DISTINCT fa.subject_id, fa.hadm_id, fa.hospital_expire_flag
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.subject_id = d.subject_id
   AND fa.hadm_id = d.hadm_id
  WHERE fa.rn = 1
    AND (
         (d.icd_version = 9 AND (
              REGEXP_CONTAINS(d.icd_code, r'^480') OR
              REGEXP_CONTAINS(d.icd_code, r'^481') OR
              REGEXP_CONTAINS(d.icd_code, r'^482') OR
              REGEXP_CONTAINS(d.icd_code, r'^483') OR
              REGEXP_CONTAINS(d.icd_code, r'^484') OR
              REGEXP_CONTAINS(d.icd_code, r'^485') OR
              REGEXP_CONTAINS(d.icd_code, r'^486') OR
              d.icd_code = '4870'
         ))
         OR
         (d.icd_version = 10 AND (
              REGEXP_CONTAINS(d.icd_code, r'^J12') OR
              REGEXP_CONTAINS(d.icd_code, r'^J13') OR
              REGEXP_CONTAINS(d.icd_code, r'^J14') OR
              REGEXP_CONTAINS(d.icd_code, r'^J15') OR
              REGEXP_CONTAINS(d.icd_code, r'^J16') OR
              REGEXP_CONTAINS(d.icd_code, r'^J17') OR
              REGEXP_CONTAINS(d.icd_code, r'^J18')
         ))
    )
)
SELECT
  COUNT(*) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_percent
FROM pneumonia_first_admissions;