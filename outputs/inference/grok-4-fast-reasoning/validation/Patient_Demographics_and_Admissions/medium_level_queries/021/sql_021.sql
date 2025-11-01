WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital mortality'
      WHEN a.discharge_location = 'DISCH HOME' THEN 'discharged home'
      WHEN a.discharge_location IN ('SNF', 'REHAB/DISTINCT PART HOSP', 'LT C FACILITY', 'OTHER FACILITY') THEN 'discharged to facility'
      ELSE NULL
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_type IN ('ELECTIVE', 'URGENT')
    AND a.dischtime IS NOT NULL
    AND EXTRACT(YEAR FROM a.admittime) - 2008 + p.anchor_age BETWEEN 67 AND 77
)

SELECT
  discharge_group,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(STDDEV(los), 2) AS sd_los,
  ROUND(100.0 * COUNTIF(los <= 7) / COUNT(*), 2) AS pct_los_le_7_days
FROM
  cohort
WHERE
  discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  discharge_group;