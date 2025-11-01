WITH sepsis_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      -- ICD-9 sepsis (excluding shock)
      (d.icd_version = 9 AND d.icd_code = '995.92')
      OR
      -- ICD-10 sepsis without shock
      (d.icd_version = 10 AND d.icd_code IN ('A41.9', 'R65.20'))
    )
    -- Exclude septic shock
    AND NOT (
      (d.icd_version = 9 AND d.icd_code = '785.52')
      OR
      (d.icd_version = 10 AND d.icd_code = 'R65.21')
    )
    -- Ensure we have valid times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_groups AS (
  SELECT
    *,
    CASE 
      WHEN hospital_los < 8 THEN '<8'
      ELSE '≥8'
    END AS los_group
  FROM sepsis_patients
  WHERE hospital_los IS NOT NULL
),
mortality_stats AS (
  SELECT
    los_group,
    SUM(hospital_expire_flag) AS deaths,
    COUNT(*) AS total,
    SUM(hospital_expire_flag) * 1.0 / COUNT(*) AS mortality_rate
  FROM los_groups
  GROUP BY los_group
)
SELECT
  los_group,
  ROUND(100.0 * mortality_rate, 2) AS mortality_rate_percent,
  ROUND(100.0 * (mortality_rate - 1.96 * SQRT(mortality_rate * (1 - mortality_rate) / total)), 2) AS ci_lower,
  ROUND(100.0 * (mortality_rate + 1.96 * SQRT(mortality_rate * (1 - mortality_rate) / total)), 2) AS ci_upper,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 1 THEN hospital_los END, 2)[OFFSET(1)] AS median_time_to_death_days
FROM los_groups
JOIN mortality_stats USING (los_group)
GROUP BY los_group, mortality_rate, total
ORDER BY los_group;