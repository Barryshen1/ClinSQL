WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age + DATE_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + DATE_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) BETWEEN 87 AND 97
),

chest_pain_admits AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      LOWER(dd.long_title) LIKE '%chest pain%'
      OR LOWER(dd.long_title) LIKE '%chest discomfort%'
      OR d.icd_code IN ('R079', '78659')
    )
),

troponin_labs AS (
  SELECT
    l.hadm_id,
    l.valuenum AS first_tnt_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND LOWER(d.label) LIKE '%hs%'
    AND l.valuenum IS NOT NULL
),

index_tnt AS (
  SELECT
    t.hadm_id,
    t.first_tnt_value,
    CASE
      WHEN t.first_tnt_value <= 0.04 THEN 'Normal'
      WHEN t.first_tnt_value > 0.04 AND t.first_tnt_value <= 0.1 THEN 'Borderline'
      ELSE 'Injury'
    END AS tnt_category
  FROM
    troponin_labs t
  WHERE
    t.rn = 1
)

SELECT
  tnt_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(first_tnt_value), 4) AS mean_value,
  ROUND(APPROX_QUANTILES(first_tnt_value, 2)[OFFSET(1)], 4) AS median_value,
  ROUND(APPROX_QUANTILES(first_tnt_value, 4)[OFFSET(1)], 4) AS q1_value,
  ROUND(APPROX_QUANTILES(first_tnt_value, 4)[OFFSET(3)], 4) AS q3_value,
  ROUND(APPROX_QUANTILES(first_tnt_value, 4)[OFFSET(3)] - APPROX_QUANTILES(first_tnt_value, 4)[OFFSET(1)], 4) AS iqr_value
FROM
  index_tnt
JOIN
  chest_pain_admits c
ON
  index_tnt.hadm_id = c.hadm_id
GROUP BY
  tnt_category
ORDER BY
  CASE tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Injury' THEN 3
  END;