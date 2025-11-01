WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
    AND di.long_title LIKE '%sepsis%'
    AND di.long_title NOT LIKE '%septic shock%'
)
SELECT
  ROUND(100 * SUM(CASE WHEN los <= 7 AND hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) / COUNT(CASE WHEN los <= 7 THEN 1.0 END), 2) AS mortality_rate_los_le7,
  ROUND(100 * SUM(CASE WHEN los > 7 AND hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) / COUNT(CASE WHEN los > 7 THEN 1.0 END), 2) AS mortality_rate_los_gt7,
  ROUND(100 * (SUM(CASE WHEN los <= 7 AND hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) / COUNT(CASE WHEN los <= 7 THEN 1.0 END) - SUM(CASE WHEN los > 7 AND hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) / COUNT(CASE WHEN los > 7 THEN 1.0 END)), 2) AS absolute_difference,
  ROUND(100 * ( (SUM(CASE WHEN los <= 7 AND hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) / COUNT(CASE WHEN los <= 7 THEN 1.0 END) - SUM(CASE WHEN los > 7 AND hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) / COUNT(CASE WHEN los > 7 THEN 1.0 END)) / (SUM(CASE WHEN los > 7 AND hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) / COUNT(CASE WHEN los > 7 THEN 1.0 END)) ), 2) AS relative_difference,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY death_time) AS median_time_to_death
FROM (
  SELECT
    c.hadm_id,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los,
    c.hospital_expire_flag,
    CASE WHEN c.deathtime IS NOT NULL THEN DATE_DIFF(c.deathtime, c.admittime, DAY) END AS death_time
  FROM cohort c
) sub;