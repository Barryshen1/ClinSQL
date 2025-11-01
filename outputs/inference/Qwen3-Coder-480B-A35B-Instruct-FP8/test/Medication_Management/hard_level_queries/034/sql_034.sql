WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los,
    p.anchor_age,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.admission_type = 'SURGICAL'
),

meds_first24h AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT e.medication) AS unique_drugs,
    COUNT(DISTINCT CASE
      WHEN REGEXP_CONTAINS(LOWER(e.medication), r'heparin|warfarin|lovenox|enoxaparin|coumadin') THEN e.medication
      WHEN REGEXP_CONTAINS(LOWER(e.medication), r'norepinephrine|epinephrine|dopamine|dobutamine|vasopressin') THEN e.medication
    END) AS high_risk_classes
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON
    c.hadm_id = e.hadm_id
  WHERE
    e.charttime >= c.admittime
    AND e.charttime <= c.admittime + INTERVAL 24 HOUR
  GROUP BY
    c.hadm_id
),

med_complexity AS (
  SELECT
    hadm_id,
    unique_drugs + (2 * high_risk_classes) AS med_complexity_score
  FROM
    meds_first24h
),

quartiles AS (
  SELECT
    c.*,
    COALESCE(m.med_complexity_score, 0) AS med_complexity_score,
    NTILE(4) OVER (ORDER BY COALESCE(m.med_complexity_score, 0)) AS complexity_quartile
  FROM
    cohort c
  LEFT JOIN
    med_complexity m
  ON
    c.hadm_id = m.hadm_id
),

readmissions AS (
  SELECT
    q1.hadm_id,
    CASE
      WHEN q2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_30_days
  FROM
    quartiles q1
  LEFT JOIN
    quartiles q2
  ON
    q1.subject_id = q2.subject_id
    AND q2.admittime > q1.dischtime
    AND q2.admittime <= q1.dischtime + INTERVAL 30 DAY
)

SELECT
  q.complexity_quartile,
  COUNT(*) AS admission_count,
  AVG(q.los) AS mean_los,
  AVG(CAST(q.hospital_expire_flag AS FLOAT64)) * 100 AS in_hosp_mortality_pct,
  AVG(CAST(r.readmit_30_days AS FLOAT64)) * 100 AS readmit_30_days_pct
FROM
  quartiles q
JOIN
  readmissions r
ON
  q.hadm_id = r.hadm_id
GROUP BY
  q.complexity_quartile
ORDER BY
  q.complexity_quartile;