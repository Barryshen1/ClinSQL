WITH patient_base AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
),
ugib AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%'
     OR LOWER(dd.long_title) LIKE '%hematemesis%'
),
copd_exac AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chronic obstructive%'
    AND LOWER(dd.long_title) LIKE '%exacerbation%'
)
SELECT
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0) AS avg_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN patient_base pb
  ON a.subject_id = pb.subject_id
JOIN ugib u
  ON a.subject_id = u.subject_id AND a.hadm_id = u.hadm_id
JOIN copd_exac c
  ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
WHERE a.dischtime IS NOT NULL;