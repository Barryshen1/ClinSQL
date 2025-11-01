WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8 days' 
      ELSE '>=8 days' 
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
stats AS (
  SELECT 
    los_group,
    COUNT(*) AS N,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_pct
  FROM cohort
  GROUP BY los_group
),
median_ttd AS (
  SELECT 
    APPROX_QUANTILES(
      TIMESTAMP_DIFF(deathtime, admittime, HOUR) / 24.0, 
      2
    )[OFFSET(1)] AS median_time_to_death_days
  FROM cohort
  WHERE hospital_expire_flag = 1
)
SELECT 
  s.los_group,
  s.N,
  s.mortality_rate_pct,
  m.median_time_to_death_days
FROM stats s
CROSS JOIN median_ttd m
ORDER BY 
  CASE los_group WHEN '<8 days' THEN 1 ELSE 2 END;