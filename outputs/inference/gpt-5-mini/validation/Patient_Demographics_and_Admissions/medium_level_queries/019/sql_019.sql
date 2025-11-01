SELECT
  category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS sd_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(COALESCE(a.discharge_location, '')) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(COALESCE(a.discharge_location, '')) LIKE '%home%'
           AND LOWER(COALESCE(a.discharge_location, '')) NOT LIKE '%homeless%' THEN 'discharged home'
      ELSE NULL
    END AS category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE (p.gender = 'F' OR LOWER(p.gender) = 'female')
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
    -- transferred from another hospital (text-match to be robust)
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer%'
    AND LOWER(COALESCE(a.admission_location, '')) LIKE '%hospital%'
)
WHERE category IS NOT NULL
GROUP BY category
ORDER BY category;