WITH surg_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    (SELECT hadm_id, curr_service, transfertime,
            ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
     FROM `physionet-data.mimiciv_3_1_hosp.services`) s
  ON
    a.hadm_id = s.hadm_id AND s.rn = 1
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + DATE_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)) BETWEEN 67 AND 77
    AND s.curr_service LIKE 'SURG%'
    AND a.dischtime IS NOT NULL
    AND a.discharge_location IS NOT NULL
),

discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN discharge_location = 'HOME' THEN 'Discharged home'
      ELSE 'Discharged to facility'
    END AS outcome_group
  FROM
    surg_admissions
)

SELECT
  outcome_group,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS stddev_los,
  AVG(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) * 100 AS pct_los_le_7
FROM
  discharge_groups
GROUP BY
  outcome_group
ORDER BY
  outcome_group;