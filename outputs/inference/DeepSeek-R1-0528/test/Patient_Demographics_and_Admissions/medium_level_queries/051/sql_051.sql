SELECT
  discharge_location,
  COUNT(*) AS total_admissions,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days,
  COUNTIF(los_days <= 7) AS admissions_los_leq_7,
  ROUND(COUNTIF(los_days <= 7) * 100.0 / COUNT(*), 2) AS percent_los_leq_7
FROM (
  SELECT
    adm.discharge_location,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND adm.admission_location LIKE '%Emergency Room%'
    AND pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year BETWEEN 68 AND 78
) AS cohort
GROUP BY discharge_location
ORDER BY discharge_location;