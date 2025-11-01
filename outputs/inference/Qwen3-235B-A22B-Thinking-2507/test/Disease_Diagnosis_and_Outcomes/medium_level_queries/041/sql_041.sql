WITH sepsis_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_version = 10
      GROUP BY hadm_id
      HAVING 
        SUM(CASE WHEN icd_code IN (
          'A400','A401','A402','A403','A404','A408','A409',
          'A410','A411','A412','A413','A414','A415','A418','A419',
          'R6520') THEN 1 ELSE 0 END) > 0
        AND SUM(CASE WHEN icd_code = 'R6521' THEN 1 ELSE 0 END) = 0
    )
),
cohort_with_los AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60.0) AS los_days,
    CASE WHEN hospital_expire_flag = 1 
         THEN TIMESTAMP_DIFF(deathtime, admittime, SECOND) / (24*60*60.0)
         ELSE NULL 
    END AS time_to_death_days
  FROM sepsis_cohort
),
group_stats AS (
  SELECT 
    CASE WHEN los_days <= 7 THEN 'le7' ELSE 'gt7' END AS los_group,
    COUNT(*) AS total,
    SUM(hospital_expire_flag) AS deaths,
    (SUM(hospital_expire_flag) * 100.0) / COUNT(*) AS mortality_rate
  FROM cohort_with_los
  GROUP BY los_group
),
pivot_stats AS (
  SELECT 
    MAX(CASE WHEN los_group = 'le7' THEN mortality_rate ELSE NULL END) AS mortality_le7,
    MAX(CASE WHEN los_group = 'gt7' THEN mortality_rate ELSE NULL END) AS mortality_gt7,
    MAX(CASE WHEN los_group = 'le7' THEN deaths ELSE NULL END) AS deaths_le7,
    MAX(CASE WHEN los_group = 'gt7' THEN deaths ELSE NULL END) AS deaths_gt7,
    MAX(CASE WHEN los_group = 'le7' THEN total ELSE NULL END) AS total_le7,
    MAX(CASE WHEN los_group = 'gt7' THEN total ELSE NULL END) AS total_gt7
  FROM group_stats
),
diff_stats AS (
  SELECT 
    mortality_le7,
    mortality_gt7,
    mortality_gt7 - mortality_le7 AS absolute_diff,
    CASE 
      WHEN mortality_le7 > 0 THEN (mortality_gt7 - mortality_le7) / mortality_le7 
      ELSE NULL 
    END AS relative_diff
  FROM pivot_stats
),
median_time AS (
  SELECT 
    APPROX_QUANTILES(time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death
  FROM cohort_with_los
  WHERE time_to_death_days IS NOT NULL
)
SELECT 
  d.mortality_le7,
  d.mortality_gt7,
  d.absolute_diff,
  d.relative_diff,
  m.median_time_to_death
FROM diff_stats d
CROSS JOIN median_time m;