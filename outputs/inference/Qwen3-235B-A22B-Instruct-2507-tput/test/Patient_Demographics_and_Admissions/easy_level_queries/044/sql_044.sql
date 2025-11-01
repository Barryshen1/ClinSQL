WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
),
age_at_admission AS (
  SELECT
    subject_id,
    hospital_expire_flag,
    gender,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admit
  FROM
    first_admissions
  WHERE
    rn = 1  -- Only the first admission
)
SELECT
  PERCENTILE_DISC(hospital_expire_flag, 0.25) AS percentile_25
FROM
  age_at_admission
WHERE
  gender = 'M'
  AND age_at_admit >= 73
  AND age_at_admit <= 83;