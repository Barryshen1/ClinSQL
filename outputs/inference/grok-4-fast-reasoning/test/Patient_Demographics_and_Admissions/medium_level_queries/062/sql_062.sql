SELECT
  discharge_group,
  COUNT(*) AS total_n,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) AS n_los_ge7,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_los_ge7,
  SUM(CASE WHEN los <= 14 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_los_le14_14day_percentile
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag,
    a.discharge_location,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location IN ('HOME', 'Home Health Care') THEN 'Home'
      WHEN a.discharge_location IN ('SNF', 'Rehab/Distinct Part Hosp', 'LTAC') THEN 'SNF/rehab/LTACH'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (
      EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age
    ) BETWEEN 64 AND 74
    AND a.dischtime IS NOT NULL
    AND (
      (a.hospital_expire_flag = 1)
      OR (
        a.discharge_location IN (
          'HOME', 'Home Health Care',
          'SNF', 'Rehab/Distinct Part Hosp', 'LTAC'
        )
      )
    )
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0
) AS sub
WHERE
  discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  discharge_group
;