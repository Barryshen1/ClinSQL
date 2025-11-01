WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
)
, cohort AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions AS fa
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON fa.subject_id = p.subject_id
  WHERE
    fa.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
)
SELECT
  quantiles[OFFSET(1)] AS mortality_25th_percentile
FROM (
  SELECT
    APPROX_QUANTILES(hospital_expire_flag, 4) AS quantiles
  FROM
    cohort
);