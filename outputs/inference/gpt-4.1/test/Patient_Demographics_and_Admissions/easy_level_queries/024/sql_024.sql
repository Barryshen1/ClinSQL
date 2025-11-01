WITH female_35_45 AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
),
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM (
    SELECT
      subject_id,
      MIN(admittime) AS first_admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY
      subject_id
  ) fa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.subject_id = fa.subject_id
    AND a.admittime = fa.first_admittime
),
cabg_first_admissions AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
    JOIN female_35_45 f ON fa.subject_id = f.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      ON fa.subject_id = pi.subject_id
      AND fa.hadm_id = pi.hadm_id
  WHERE
    pi.icd_version = 9
    AND pi.icd_code LIKE '36.1%'
)
SELECT
  COUNT(*) AS n_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS in_hospital_mortality_rate
FROM
  cabg_first_admissions;