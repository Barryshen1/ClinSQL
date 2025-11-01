WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admission_type != 'OUTPATIENT'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
),

-- Identify neutropenic fever admissions
neutropenic_admissions AS (
  SELECT DISTINCT
    c.hadm_id
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    c.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    le.itemid = d.itemid
  WHERE
    d.label IN ('Neutrophils', 'ANC')
    AND le.valuenum < 500
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
),

febrile_admissions AS (
  SELECT DISTINCT
    c.hadm_id
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    c.hadm_id = ce.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    di.label IN ('Temperature', 'Temp')
    AND ce.valuenum >= 38.0
    AND ce.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
),

neutropenic_fever AS (
  SELECT
    n.hadm_id
  FROM
    neutropenic_admissions n
  JOIN
    febrile_admissions f
  ON
    n.hadm_id = f.hadm_id
),

-- Medication complexity score: distinct meds in first 48h
meds_48h AS (
  SELECT
    e.hadm_id,
    COUNT(DISTINCT e.medication) AS med_complexity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN
    cohort c
  ON
    e.hadm_id = c.hadm_id
  WHERE
    e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY
    e.hadm_id
),

-- Add quartiles
admissions_with_quartiles AS (
  SELECT
    c.*,
    m.med_complexity_score,
    NTILE(4) OVER (ORDER BY m.med_complexity_score) AS med_quartile
  FROM
    cohort c
  JOIN
    meds_48h m
  ON
    c.hadm_id = m.hadm_id
),

-- 30-day readmission flag
readmissions AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmit_30
  FROM
    admissions_with_quartiles a1
  LEFT JOIN
    admissions_with_quartiles a2
  ON
    a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
)

-- Final aggregation
SELECT
  med_quartile,
  COUNT(*) AS patient_count,
  AVG(med_complexity_score) AS mean_med_score,
  MIN(med_complexity_score) AS min_med_score,
  MAX(med_complexity_score) AS max_med_score,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmit_30) * 100 AS readmit_30_pct
FROM
  admissions_with_quartiles aq
LEFT JOIN
  readmissions r
ON
  aq.hadm_id = r.hadm_id
GROUP BY
  med_quartile
ORDER BY
  med_quartile;