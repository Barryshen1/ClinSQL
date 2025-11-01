WITH stroke_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  -- join to get diagnosis strings, for possible clarity/filter
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dx
    ON d.icd_code = dx.icd_code
    AND d.icd_version = dx.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.seq_num = 1
    AND (
         -- ICD-9 ischemic stroke
         (d.icd_version = 9 AND (
             REGEXP_CONTAINS(d.icd_code, r'^433.*1$') OR
             REGEXP_CONTAINS(d.icd_code, r'^434.*1$') OR
             d.icd_code = '436'
         ))
         OR
         -- ICD-10 ischemic stroke: I63.*, I64
         (d.icd_version = 10 AND (
             REGEXP_CONTAINS(d.icd_code, r'^I63') OR
             d.icd_code = 'I64'
         ))
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  ROUND(q[3] - q[1], 2) AS iqr_los_days
FROM (
  SELECT
    APPROX_QUANTILES(los_days, 4) AS q
  FROM stroke_patients
);