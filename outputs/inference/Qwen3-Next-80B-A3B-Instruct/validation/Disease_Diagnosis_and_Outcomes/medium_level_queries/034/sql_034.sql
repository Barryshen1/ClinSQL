WITH heart_failure_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND LOWER(did.long_title) LIKE '%heart failure%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_groups AS (
  SELECT
    hadm_id,
    los_days,
    hospital_expire_flag,
    deathtime,
    admittime,
    CASE
      WHEN los_days < 8 THEN '<8 days'
      ELSE '>=8 days'
    END AS los_group
  FROM
    heart_failure_admissions
)
SELECT
  los_group,
  COUNT(*) AS admission_count,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_rate_percent,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 1 THEN EXTRACT(DAY FROM (deathtime - admittime)) END, 1)[OFFSET(0)] AS median_time_to_death_days
FROM
  los_groups
GROUP BY
  los_group
ORDER BY
  los_group;