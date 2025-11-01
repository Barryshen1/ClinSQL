SELECT 
  disposition_group,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(90)] AS p90_los,
  (SUM(CASE WHEN los < 5 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS pct_less_than_5_days
FROM (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location = 'Home' THEN 'home'
      WHEN a.discharge_location = 'Hospice care' THEN 'hospice'
      ELSE 'other'
    END AS disposition_group,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND a.admission_type NOT IN ('Emergency', 'Trauma')
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
) 
WHERE disposition_group IN ('home', 'hospice', 'in-hospital death')
GROUP BY disposition_group
ORDER BY disposition_group;