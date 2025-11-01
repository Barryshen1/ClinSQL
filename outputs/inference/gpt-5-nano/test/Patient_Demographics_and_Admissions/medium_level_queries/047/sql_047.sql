SELECT
  discharge_group,
  ROUND(AVG(los_days), 4) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 4) AS sd_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS percentile_rank_5day
FROM (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    /* LOS in days as a floating number */
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    /* categorize outcome groups */
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'InHospitalDeath'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%facility%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE
    LOWER(a.admission_type) LIKE '%transfer%' -- transferred in
    AND p.anchor_age BETWEEN 52 AND 62
    AND UPPER(p.gender) IN ('F', 'FEMALE')
    AND a.dischtime IS NOT NULL
) AS sub
WHERE discharge_group IN ('Home', 'Facility', 'InHospitalDeath')
GROUP BY discharge_group
ORDER BY discharge_group;