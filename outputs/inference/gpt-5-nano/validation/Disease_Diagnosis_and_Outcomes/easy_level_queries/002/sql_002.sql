WITH aki_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND di.seq_num = 1
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '584%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  quantiles[OFFSET(75)] AS p75_hospital_los_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM aki_admissions
);