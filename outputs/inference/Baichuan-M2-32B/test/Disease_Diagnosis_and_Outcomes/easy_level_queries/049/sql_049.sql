WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.dischtime IS NOT NULL
),
stroke_admissions AS (
  SELECT
    fa.*
  FROM
    filtered_admissions fa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fa.hadm_id = d.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (dd.long_title LIKE '%ischemic stroke%' 
         OR dd.long_title LIKE '%cerebral infarction%' 
         OR dd.long_title LIKE '%stroke, ischemic%')
    AND fa.age_at_admission BETWEEN 50 AND 60
)
SELECT
  APPROX_QUANTILES(los, 4)[OFFSET(0)] AS los_25th_percentile
FROM
  stroke_admissions;