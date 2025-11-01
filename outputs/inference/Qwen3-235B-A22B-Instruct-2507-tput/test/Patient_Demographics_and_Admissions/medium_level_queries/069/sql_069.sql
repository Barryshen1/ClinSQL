WITH cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Compute length of stay in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  -- Join with services to get the first service
  INNER JOIN (
    SELECT
      hadm_id,
      curr_service,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp`.services
  ) s
  ON
    a.hadm_id = s.hadm_id
  WHERE
    s.rn = 1  -- First service
    AND s.curr_service NOT LIKE '%SURG%'  -- Exclude surgical services
    AND a.admission_type = 'EMERGENCY'
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)
SELECT
  -- Proportion with LOS >=7 among discharged alive
  SUM(CASE WHEN hospital_expire_flag = 0 AND los_days >= 7 THEN 1 ELSE 0 END) * 1.0 
    / NULLIF(SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END), 0) AS discharged_alive_los_ge7_prop,
  -- Proportion with LOS >=7 among in-hospital deaths
  SUM(CASE WHEN hospital_expire_flag = 1 AND los_days >= 7 THEN 1 ELSE 0 END) * 1.0 
    / NULLIF(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), 0) AS in_hospital_death_los_ge7_prop,
  -- Percentile rank of 7-day LOS: % of patients with LOS <= 7
  SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS percentile_rank_of_7_days
FROM
  cohort;