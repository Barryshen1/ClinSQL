WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location = 'DISCH HOME' THEN 'discharged home'
      WHEN a.discharge_location = 'HOSPICE' THEN 'hospice'
    END AS category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admission_location = 'TRANSFER FROM HOSP'
    AND (a.hospital_expire_flag = 1 OR a.discharge_location IN ('DISCH HOME', 'HOSPICE'))
    AND a.dischtime > a.admittime  -- Ensure positive LOS
)
SELECT
  category,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS sd_los_days
FROM
  cohort
WHERE
  category IS NOT NULL
GROUP BY
  category
ORDER BY
  category;