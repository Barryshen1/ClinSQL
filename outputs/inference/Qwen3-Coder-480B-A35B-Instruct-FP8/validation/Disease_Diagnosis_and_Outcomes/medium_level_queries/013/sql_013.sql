WITH adhf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code IN (
      'I5021', 'I5023', 'I5031', 'I5033', 'I5041', 'I5043', -- ICD-10
      '4280', '42820', '42821', '42823', '42830', '42831', '42832', '42833',
      '42840', '42841', '42842', '42843' -- ICD-9
    )
),
filtered_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    adhf_admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
los_groups AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE 'Other'
    END AS los_group
  FROM
    filtered_patients
  WHERE
    los_days >= 1
),
mortality_stats AS (
  SELECT
    los_group,
    COUNT(*) AS total,
    SUM(hospital_expire_flag) AS deaths,
    APPROX_QUANTILES(
      CASE WHEN hospital_expire_flag = 1 THEN DATETIME_DIFF(deathtime, admittime, HOUR) END,
      2
    )[OFFSET(1)] AS median_time_to_death_hours
  FROM
    los_groups
  GROUP BY
    los_group
)
SELECT
  los_group,
  total,
  deaths,
  ROUND(100 * deaths / total, 2) AS mortality_percent,
  ROUND(100 * (deaths - 1.96 * SQRT(deaths * (1 - deaths / total)) / total), 2) AS ci_lower,
  ROUND(100 * (deaths + 1.96 * SQRT(deaths * (1 - deaths / total)) / total), 2) AS ci_upper,
  ROUND(median_time_to_death_hours / 24.0, 2) AS median_time_to_death_days
FROM
  mortality_stats
ORDER BY
  CASE los_group
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '>=8' THEN 3
  END;