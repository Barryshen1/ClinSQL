WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    a.admission_type,
    a.admission_location,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN DATE_DIFF(a.deathtime, a.admittime, DAY)
      ELSE DATE_DIFF(a.dischtime, a.admittime, DAY)
    END AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'EMERGENCY ROOM'
)
SELECT
  SUM(CASE WHEN hospital_expire_flag = 0 AND los >= 7 THEN 1 ELSE 0 END) * 1.0 / NULLIF(SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END), 0) AS proportion_alive,
  SUM(CASE WHEN hospital_expire_flag = 1 AND los >= 7 THEN 1 ELSE 0 END) * 1.0 / NULLIF(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), 0) AS proportion_dead,
  (SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) * 100 AS percentile_rank
FROM cohort;