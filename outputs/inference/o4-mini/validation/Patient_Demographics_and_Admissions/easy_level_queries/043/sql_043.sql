WITH cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
)
SELECT
  quantiles[OFFSET(1)] AS p25_mortality,
  quantiles[OFFSET(3)] AS p75_mortality,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_mortality
FROM (
  SELECT
    APPROX_QUANTILES(hospital_expire_flag, 4) AS quantiles
  FROM
    cohort
);