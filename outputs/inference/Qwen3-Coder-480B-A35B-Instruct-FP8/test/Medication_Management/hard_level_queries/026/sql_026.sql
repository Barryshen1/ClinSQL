WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      dd.icd_code LIKE 'J18%' OR
      dd.icd_code LIKE 'J15%' OR
      dd.icd_code LIKE 'J12%' OR
      dd.icd_code LIKE 'J13%' OR
      dd.icd_code LIKE 'J14%' OR
      dd.icd_code LIKE 'J15%' OR
      dd.icd_code LIKE 'J16%' OR
      dd.icd_code LIKE 'J17%'
    )
),

meds_first7d AS (
  SELECT
    e.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN
    cohort c
  ON
    e.hadm_id = c.hadm_id
  WHERE
    e.charttime >= c.admittime
    AND e.charttime <= DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY
    e.hadm_id
),

tertiles AS (
  SELECT
    c.*,
    m.med_count,
    NTILE(3) OVER (ORDER BY m.med_count) AS med_tertile
  FROM
    cohort c
  JOIN
    meds_first7d m
  ON
    c.hadm_id = m.hadm_id
),

readmissions AS (
  SELECT
    t1.hadm_id,
    CASE
      WHEN t2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_30
  FROM
    tertiles t1
  LEFT JOIN
    tertiles t2
  ON
    t1.subject_id = t2.subject_id
    AND t2.admittime > t1.dischtime
    AND DATETIME_DIFF(t2.admittime, t1.dischtime, DAY) <= 30
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY t1.hadm_id ORDER BY t2.admittime) = 1
)

SELECT
  med_tertile,
  COUNT(*) AS admission_count,
  MIN(med_count) AS min_med_count,
  AVG(med_count) AS avg_med_count,
  MAX(med_count) AS max_med_count,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS in_hosp_mortality_pct,
  AVG(readmit_30) * 100 AS readmit_30_pct
FROM
  tertiles t
JOIN
  readmissions r
ON
  t.hadm_id = r.hadm_id
GROUP BY
  med_tertile
ORDER BY
  med_tertile;