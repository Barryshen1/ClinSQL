WITH non_icu_adms AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.admissions AS a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp`.patients AS p
    ON a.subject_id = p.subject_id
  WHERE 
    a.dischtime IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.hadm_id NOT IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_icu`.icustays 
      WHERE hadm_id IS NOT NULL
    )
)
SELECT 
  category,
  AVG(los) AS mean_los_days,
  STDDEV(los) AS sd_los_days
FROM (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM non_icu_adms
  WHERE TIMESTAMP_DIFF(dischtime, admittime, DAY) > 0
) AS filtered
CROSS JOIN UNNEST([STRUCT(
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
    WHEN discharge_location = 'DISCHARGED TO HOME' THEN 'Discharged Home'
    WHEN discharge_location LIKE '%HOSPICE%' THEN 'Discharged to Hospice'
    ELSE NULL
  END AS category
)])
WHERE category IS NOT NULL
GROUP BY category
ORDER BY category;