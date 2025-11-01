WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 <= 3 THEN '1-3'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 <= 7 THEN '4-7'
      ELSE '>=8' 
    END AS los_group,
    IF(a.hospital_expire_flag = 1, 
       TIMESTAMP_DIFF(a.deathtime, a.admittime, HOUR) / 24.0, 
       NULL) AS days_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = '9' AND d.icd_code LIKE '428%') 
          OR 
          (d.icd_version = '10' AND d.icd_code LIKE 'I50%')
        )
    )
),
base_summary AS (
  SELECT 
    los_group,
    COUNT(*) AS total,
    SUM(hospital_expire_flag) AS deaths
  FROM cohort
  GROUP BY los_group
),
summary AS (
  SELECT 
    los_group,
    total,
    deaths,
    ROUND(SAFE_DIVIDE(deaths, total) * 100, 2) AS mortality_pct,
    ROUND(
      GREATEST(0, 
        ((deaths + (1.96 * 1.96) / 2.0) / (total + 1.96 * 1.96) 
         - 1.96 * SQRT(
             (deaths * (total - deaths) / CAST(total AS FLOAT64) + (1.96 * 1.96) / 4.0) 
             / POWER(total + 1.96 * 1.96, 2)
           )) * 100
      ), 2
    ) AS ci_lower_pct,
    ROUND(
      LEAST(100, 
        ((deaths + (1.96 * 1.96) / 2.0) / (total + 1.96 * 1.96) 
         + 1.96 * SQRT(
             (deaths * (total - deaths) / CAST(total AS FLOAT64) + (1.96 * 1.96) / 4.0) 
             / POWER(total + 1.96 * 1.96, 2)
           )) * 100
      ), 2
    ) AS ci_upper_pct
  FROM base_summary
),
medians AS (
  SELECT 
    los_group,
    ROUND(PERCENTILE_CONT(days_to_death, 0.5), 1) AS median_ttd_days
  FROM cohort
  WHERE hospital_expire_flag = 1
  GROUP BY los_group
)
SELECT 
  s.los_group,
  s.total,
  s.deaths,
  s.mortality_pct,
  s.ci_lower_pct,
  s.ci_upper_pct,
  m.median_ttd_days
FROM summary s
LEFT JOIN medians m 
  ON s.los_group = m.los_group
ORDER BY 
  CASE los_group 
    WHEN '1-3' THEN 1 
    WHEN '4-7' THEN 2 
    ELSE 3 
  END;