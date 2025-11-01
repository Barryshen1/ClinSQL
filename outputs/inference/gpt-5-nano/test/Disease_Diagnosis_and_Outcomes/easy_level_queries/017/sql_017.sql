WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
diagnosis AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    di.icd_code,
    di.icd_version,
    dd.long_title
  FROM base AS b
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = b.subject_id
   AND di.hadm_id = b.hadm_id
   AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE LOWER(dd.long_title) LIKE '%ischemic%'
     OR LOWER(dd.long_title) LIKE '%cerebral infarction%'
     OR LOWER(dd.long_title) LIKE '%ischemia%'
     OR LOWER(dd.long_title) LIKE '%ischemic stroke%'
)
SELECT
  MAX(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS max_hospital_los_days
FROM diagnosis;