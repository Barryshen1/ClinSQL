WITH sepsis_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.icd_version = 10
    AND (
      dd.icd_code LIKE 'A41%'
      OR dd.icd_code LIKE 'R65.2%'
      AND dd.icd_code != 'R65.23'
    )
),

mortality_stats AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    los_days,
    CASE WHEN los_days <= 7 THEN 'LOS <= 7' ELSE 'LOS > 7' END AS los_group,
    CASE
      WHEN hospital_expire_flag = 1 THEN DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0
      ELSE NULL
    END AS days_to_death
  FROM
    sepsis_cohort
),

grouped_stats AS (
  SELECT
    los_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    APPROX_QUANTILES(days_to_death, 2 IGNORE NULLS)[OFFSET(1)] AS median_time_to_death
  FROM
    mortality_stats
  GROUP BY
    los_group
),

pivot_stats AS (
  SELECT
    MAX(CASE WHEN los_group = 'LOS <= 7' THEN mortality_percent END) AS mortality_leq_7,
    MAX(CASE WHEN los_group = 'LOS > 7' THEN mortality_percent END) AS mortality_gt_7,
    MAX(CASE WHEN los_group = 'LOS <= 7' THEN median_time_to_death END) AS median_ttd_leq_7,
    MAX(CASE WHEN los_group = 'LOS > 7' THEN median_time_to_death END) AS median_ttd_gt_7
  FROM
    grouped_stats
)

SELECT
  mortality_leq_7,
  mortality_gt_7,
  mortality_leq_7 - mortality_gt_7 AS abs_diff_mortality,
  SAFE_DIVIDE(mortality_leq_7 - mortality_gt_7, mortality_gt_7) * 100 AS rel_diff_mortality_percent,
  median_ttd_leq_7,
  median_ttd_gt_7
FROM
  pivot_stats;