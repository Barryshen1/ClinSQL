WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
),

meds_first24 AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= c.admittime
    AND pr.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY
    c.hadm_id
),

readmissions AS (
  SELECT
    c1.hadm_id,
    CASE
      WHEN c2.admittime IS NOT NULL
        AND DATETIME_DIFF(c2.admittime, c1.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmit_30_days
  FROM
    cohort c1
  LEFT JOIN
    cohort c2
  ON
    c1.subject_id = c2.subject_id
    AND c2.admittime > c1.dischtime
    AND DATETIME_DIFF(c2.admittime, c1.dischtime, DAY) <= 30
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY c1.hadm_id ORDER BY c2.admittime ASC) = 1
),

final_data AS (
  SELECT
    c.hadm_id,
    m.complexity_score,
    NTILE(5) OVER (ORDER BY m.complexity_score) AS quintile,
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    c.hospital_expire_flag AS died_in_hosp,
    COALESCE(r.readmit_30_days, 0) AS readmit_30_days
  FROM
    cohort c
  JOIN
    meds_first24 m
  ON
    c.hadm_id = m.hadm_id
  LEFT JOIN
    readmissions r
  ON
    c.hadm_id = r.hadm_id
)

SELECT
  quintile,
  COUNT(*) AS n_patients,
  AVG(complexity_score) AS mean_complexity_score,
  AVG(los_days) AS avg_los_days,
  AVG(died_in_hosp) AS in_hosp_mortality,
  AVG(readmit_30_days) AS readmit_30_rate
FROM
  final_data
GROUP BY
  quintile
ORDER BY
  quintile;