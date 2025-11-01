WITH first_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
)

SELECT
  PERCENTILE_CONT(mortality_rate, 0.25) OVER() AS percentile_25_mortality
FROM (
  SELECT
    subject_id,
    CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality_rate
  FROM
    first_admissions
  WHERE
    admission_rank = 1
)
LIMIT 1;