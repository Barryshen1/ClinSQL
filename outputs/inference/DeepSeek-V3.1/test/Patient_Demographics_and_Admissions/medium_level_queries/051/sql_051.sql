WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.discharge_location,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.dischtime IS NOT NULL
)

SELECT 
  discharge_location,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days), 2) AS avg_los,
  ROUND(STDDEV(los_days), 2) AS std_los,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_short_stay
FROM cohort
GROUP BY discharge_location
ORDER BY discharge_location;