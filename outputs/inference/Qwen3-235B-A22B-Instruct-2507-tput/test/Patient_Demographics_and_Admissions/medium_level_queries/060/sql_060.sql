WITH patient_los AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.admission_location LIKE '%EMERGENCY%'
    AND a.dischtime IS NOT NULL
),
filtered_los AS (
  SELECT
    *,
    -- Categorize outcome: prioritize death
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) IN ('home', 'home with home health', 'home - health care', 'home health', 'home care') THEN 'Home'
      ELSE NULL
    END AS discharge_group
  FROM patient_los
  WHERE age_at_admit BETWEEN 50 AND 60
)
SELECT
  discharge_group,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days,
  AVG(CASE WHEN los_days <= 10 THEN 1.0 ELSE 0.0 END) * 100 AS percent_los_le_10_days
FROM filtered_los
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY discharge_group;