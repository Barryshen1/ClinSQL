WITH admitted_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
classified_admissions AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOME%' OR discharge_location = 'HOME' OR discharge_location = 'HOME WITH HOME CARE' THEN 'Discharged home'
      WHEN discharge_location LIKE '%FACILITY%' OR discharge_location LIKE '%REHAB%' OR discharge_location LIKE '%SNF%' OR discharge_location LIKE '%LONG TERM CARE%' OR discharge_location = 'SKILLED NURSING FACILITY' THEN 'To facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    admitted_patients
  WHERE
    discharge_location IS NOT NULL OR hospital_expire_flag = 1
)
SELECT
  discharge_category,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS proportion_los_ge7,
  SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_rank_7day_los
FROM
  classified_admissions
WHERE
  discharge_category IN ('Discharged home', 'To facility', 'In-hospital death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;