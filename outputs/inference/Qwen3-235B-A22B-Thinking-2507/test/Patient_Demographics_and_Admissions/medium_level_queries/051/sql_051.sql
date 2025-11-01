SELECT
  discharge_location,
  AVG(los) AS mean_los,
  STDDEV(los) AS sd_los,
  (COUNTIF(los <= 7) * 100.0) / COUNT(*) AS percent_los_le7
FROM (
  SELECT
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_location IN ('EMERGENCY ROOM ADMIT', 'TRANSFER FROM HOSPITAL EMERGENCY ROOM')
    AND a.dischtime IS NOT NULL
    AND p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 68 AND 78
)
GROUP BY discharge_location
ORDER BY discharge_location;