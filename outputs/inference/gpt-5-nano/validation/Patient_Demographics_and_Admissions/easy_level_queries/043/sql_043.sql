WITH eligible AS (
  SELECT
    a.hadm_id,
    CASE
      WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS died_in_hosp
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
quantiles_arr AS (
  SELECT APPROX_QUANTILES(died_in_hosp, 4) AS aq
  FROM eligible
)
SELECT
  CAST(aq[SAFE_OFFSET(1)] AS FLOAT64) AS p25,
  CAST(aq[SAFE_OFFSET(3)] AS FLOAT64) AS p75,
  CAST(aq[SAFE_OFFSET(3)] - aq[SAFE_OFFSET(1)] AS FLOAT64) AS iqr,
  (SELECT COUNT(*) FROM eligible) AS total_encounters
FROM quantiles_arr;