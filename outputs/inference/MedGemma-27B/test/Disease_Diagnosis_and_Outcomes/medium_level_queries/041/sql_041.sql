WITH Sepsis AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- Calculate length of stay (LOS)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 50 AND 60
    AND a.hospital_expire_flag = 1
),
SepsisDiagnosis AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'J84%' -- Sepsis code
    AND d.icd_version = 9
),
SepticShockDiagnosis AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'J84.9%' -- Septic shock code
    AND d.icd_version = 9
),
SepsisPatients AS (
  SELECT
    s.subject_id,
    s.hadm_id
  FROM
    Sepsis AS s
  LEFT JOIN
    SepsisDiagnosis AS sd
    ON s.subject_id = sd.subject_id AND s.hadm_id = sd.hadm_id
  LEFT JOIN
    SepticShockDiagnosis AS ssh
    ON s.subject_id = ssh.subject_id AND s.hadm_id = ssh.hadm_id
  WHERE
    sd.icd_code IS NOT NULL
    AND ssh.hadm_id IS NULL
),
Mortality AS (
  SELECT
    sp.subject_id,
    sp.hadm_id,
    sp.los,
    a.deathtime,
    a.dischtime
  FROM
    SepsisPatients AS sp
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON sp.subject_id = a.subject_id AND sp.hadm_id = a.hadm_id
)
SELECT
  CASE
    WHEN m.los <= 7
    THEN '≤7 days'
    ELSE '>7 days'
  END AS los_group,
  COUNT(m.subject_id) AS total_patients,
  SUM(CASE WHEN m.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS deaths,
  SUM(CASE WHEN m.deathtime IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(m.subject_id) AS mortality_percentage,
  AVG(TIMESTAMP_DIFF(m.deathtime, m.admittime, HOUR)) AS median_time_to_death
FROM
  Mortality AS m
GROUP BY
  los_group
ORDER BY
  los_group;