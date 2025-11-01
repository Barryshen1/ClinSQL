WITH candidate_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND di.seq_num = 1
    AND (
      LOWER(dd.long_title) LIKE '%ischemic stroke%'
      OR LOWER(dd.long_title) LIKE '%cerebral infarction%'
    )
)
SELECT
  (APPROX_QUANTILES(los_days, 4))[OFFSET(1)] AS p25_los_days
FROM (
  SELECT
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM candidate_admissions ca
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = ca.hadm_id
  WHERE a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
);