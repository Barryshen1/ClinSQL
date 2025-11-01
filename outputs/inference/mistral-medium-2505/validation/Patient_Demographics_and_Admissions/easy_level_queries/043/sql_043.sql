WITH female_patients_51_61 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 51 AND 61
),

admissions_with_mortality AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients_51_61 p ON a.subject_id = p.subject_id
  WHERE
    a.hospital_expire_flag IS NOT NULL
),

mortality_rates AS (
  SELECT
    hadm_id,
    hospital_expire_flag AS mortality
  FROM
    admissions_with_mortality
)

SELECT
  PERCENTILE_CONT(mortality, 0.25) OVER() AS q1,
  PERCENTILE_CONT(mortality, 0.75) OVER() AS q3,
  PERCENTILE_CONT(mortality, 0.75) OVER() - PERCENTILE_CONT(mortality, 0.25) OVER() AS iqr
FROM
  mortality_rates
LIMIT 1;