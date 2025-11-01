WITH aki_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    MIN(CASE WHEN di.seq_num = 1 THEN 1 ELSE 2 END) AS diagnosis_type -- 1=primary, 2=secondary
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
      OR (di.icd_version = 9 AND di.icd_code LIKE '584%')
    )
  GROUP BY a.subject_id, a.hadm_id, p.gender, p.anchor_age
),
los_group AS (
  SELECT
    c.*,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_bucket
  FROM aki_cohort c
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON c.hadm_id = a.hadm_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_counts AS (
  SELECT
    lg.hadm_id,
    lg.los_bucket,
    lg.diagnosis_type,
    COUNT(pic.icd_code) AS imaging_count
  FROM los_group lg
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pic
    ON lg.hadm_id = pic.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON pic.icd_code = dp.icd_code
   AND pic.icd_version = dp.icd_version
  WHERE dp.long_title IS NULL
    OR REGEXP_CONTAINS(UPPER(dp.long_title), r'(XRAY|X-RAY|CT|MRI|ULTRASOUND|IMAGING)')
  GROUP BY lg.hadm_id, lg.los_bucket, lg.diagnosis_type
),
stats AS (
  SELECT
    los_bucket,
    diagnosis_type,
    APPROX_QUANTILES(imaging_count, 4) AS quartiles
  FROM imaging_counts
  GROUP BY los_bucket, diagnosis_type
)
SELECT
  los_bucket,
  CASE diagnosis_type WHEN 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type,
  quartiles[OFFSET(0)] AS q0,
  quartiles[OFFSET(1)] AS q1, -- Q1
  quartiles[OFFSET(2)] AS median,
  quartiles[OFFSET(3)] AS q3,
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS IQR
FROM stats
ORDER BY los_bucket, diagnosis_type;