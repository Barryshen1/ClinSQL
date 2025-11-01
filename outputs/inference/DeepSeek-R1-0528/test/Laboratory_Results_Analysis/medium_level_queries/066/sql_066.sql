WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '786.5%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'R07%')
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
),
first_troponin AS (
  SELECT
    c.hadm_id,
    l.valuenum AS initial_troponin,
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY l.charttime) AS rn
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  WHERE 
    l.itemid = 51003
    AND l.valuenum IS NOT NULL
),
categorized AS (
  SELECT
    hadm_id,
    initial_troponin,
    CASE
      WHEN initial_troponin <= 14 THEN 'Normal'
      WHEN initial_troponin BETWEEN 15 AND 29 THEN 'Borderline'
      WHEN initial_troponin >= 30 THEN 'Myocardial injury'
    END AS category
  FROM first_troponin
  WHERE rn = 1
),
aggregated AS (
  SELECT
    category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized), 1) AS percentage,
    ROUND(AVG(initial_troponin), 1) AS mean,
    APPROX_QUANTILES(initial_troponin, 4) AS quantiles
  FROM categorized
  GROUP BY category
)
SELECT
  category,
  count,
  percentage,
  mean,
  quantiles[OFFSET(2)] AS median,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM aggregated
ORDER BY
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial injury' THEN 3
  END;