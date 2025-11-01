WITH sepsis_patients AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (d.icd_code IN ('995.91', '995.92', 'A41.9', 'R65.20') AND d.icd_version IN (9, 10))
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = d.hadm_id
        AND d2.icd_code IN ('785.52', 'R65.21')
        AND d2.icd_version IN (9, 10)
    )
),
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS adm_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN sepsis_patients sp ON a.hadm_id = sp.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),
mortality_data AS (
  SELECT 
    CASE WHEN los < 8 THEN '<8' ELSE '>=8' END AS los_group,
    COUNT(*) AS total,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS p
  FROM filtered_admissions
  GROUP BY los_group
),
median_data AS (
  SELECT 
    CASE WHEN los < 8 THEN '<8' ELSE '>=8' END AS los_group,
    DATE_DIFF(deathtime, admittime, DAY) AS time_to_death
  FROM filtered_admissions
  WHERE hospital_expire_flag = 1
)
SELECT 
  m.los_group,
  ROUND(m.p * 100, 2) AS mortality_rate,
  ROUND((m.p - 1.96 * SQRT(m.p * (1 - m.p) / m.total)) * 100, 2) AS lower_ci,
  ROUND((m.p + 1.96 * SQRT(m.p * (1 - m.p) / m.total)) * 100, 2) AS upper_ci,
  ROUND(md.median_time_to_death, 2) AS median_time_to_death
FROM mortality_data m
JOIN (
  SELECT 
    los_group,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY time_to_death) AS median_time_to_death
  FROM median_data
  GROUP BY los_group
) md ON m.los_group = md.los_group;