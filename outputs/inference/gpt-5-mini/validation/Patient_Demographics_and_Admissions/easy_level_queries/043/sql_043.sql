WITH cohort AS (
  SELECT
    ad.hadm_id,
    CAST(ad.hospital_expire_flag AS INT64) AS died
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND ad.hadm_id IS NOT NULL
    AND ad.hospital_expire_flag IS NOT NULL
)
SELECT
  q[OFFSET(1)] AS q1_25,
  q[OFFSET(3)] AS q3_75,
  q[OFFSET(3)] - q[OFFSET(1)] AS iqr,
  (SELECT COUNT(*) FROM cohort) AS n_encounters
FROM (
  SELECT APPROX_QUANTILES(died, 4) AS q
  FROM cohort
);