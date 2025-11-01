WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

cardiac_arrest AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    c.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code = '4275')
    OR (d.icd_version = 10 AND d.icd_code IN ('I460', 'I461', 'I469'))
),

medication_count AS (
  SELECT
    ca.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count
  FROM
    cardiac_arrest ca
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON
    ca.hadm_id = e.hadm_id
  JOIN
    cohort c
  ON
    e.hadm_id = c.hadm_id
  WHERE
    e.charttime >= c.admittime
    AND e.charttime <= DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY
    ca.hadm_id
),

quintiles AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.dischtime,
    c.los_days,
    c.hospital_expire_flag,
    COALESCE(m.med_count, 0) AS med_count,
    NTILE(5) OVER (ORDER BY COALESCE(m.med_count, 0)) AS med_quintile
  FROM
    cardiac_arrest ca
  JOIN
    cohort c
  ON
    ca.hadm_id = c.hadm_id
  LEFT JOIN
    medication_count m
  ON
    ca.hadm_id = m.hadm_id
),

readmission AS (
  SELECT
    q.hadm_id,
    CASE
      WHEN q.hospital_expire_flag = 0 AND a2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_30
  FROM
    quintiles q
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
  ON
    q.subject_id = a2.subject_id
    AND a2.admittime > q.dischtime
    AND a2.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
  WHERE
    q.hospital_expire_flag = 0
)

SELECT
  q.med_quintile,
  COUNT(*) AS patient_count,
  AVG(q.med_count) AS avg_med_count,
  MIN(q.med_count) AS min_med_count,
  MAX(q.med_count) AS max_med_count,
  AVG(q.los_days) AS avg_los,
  AVG(q.hospital_expire_flag) * 100 AS in_hosp_mortality_pct,
  AVG(r.readmit_30) * 100 AS readmit_30_pct
FROM
  quintiles q
LEFT JOIN
  readmission r
ON
  q.hadm_id = r.hadm_id
GROUP BY
  q.med_quintile
ORDER BY
  q.med_quintile;