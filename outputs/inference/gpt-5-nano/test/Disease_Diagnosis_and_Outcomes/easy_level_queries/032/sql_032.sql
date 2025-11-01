WITH aki_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 81 AND 91
    AND di.seq_num = 1
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '584%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
    )
),
aki_los AS (
  SELECT TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM aki_admissions
)
SELECT
  quantiles[OFFSET(25)] AS q1_25th_percentile_days,
  quantiles[OFFSET(75)] AS q3_75th_percentile_days,
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM aki_los
);