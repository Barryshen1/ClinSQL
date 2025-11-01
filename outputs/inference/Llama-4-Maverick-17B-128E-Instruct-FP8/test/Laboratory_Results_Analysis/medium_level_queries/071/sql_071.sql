WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 43 AND 53
),
admissions_with_troponin AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    l.charttime,
    l.valuenum,
    d.label,
    l.ref_range_lower,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_filtered p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE d.label LIKE '%Troponin T%' AND l.valuenum IS NOT NULL
),
initial_troponin AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    valuenum,
    ref_range_lower,
    ref_range_upper,
    CASE
      WHEN valuenum <= ref_range_upper THEN 'Normal'
      WHEN valuenum > ref_range_upper * 1.5 THEN 'Elevated'
      ELSE 'Borderline'
    END AS troponin_category
  FROM admissions_with_troponin
  WHERE rn = 1
),
los AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)
SELECT 
  it.troponin_category,
  COUNT(it.hadm_id) AS count,
  COUNT(it.hadm_id) * 100.0 / (SELECT COUNT(*) FROM initial_troponin) AS percentage,
  AVG(los.los_days) AS avg_los_days
FROM initial_troponin it
JOIN los ON it.hadm_id = los.hadm_id
GROUP BY it.troponin_category
ORDER BY it.troponin_category;