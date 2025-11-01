WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
    )
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 79 AND 89
),
troponin AS (
  SELECT
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort c
    ON l.hadm_id = c.hadm_id
  WHERE l.itemid = 50586
    AND l.valuenum IS NOT NULL
    AND l.charttime >= c.admittime
),
initial_trop AS (
  SELECT
    hadm_id,
    valuenum AS initial_troponin
  FROM (
    SELECT
      hadm_id,
      charttime,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin
  )
  WHERE rn = 1
),
categorized AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN it.initial_troponin <= 0.01 THEN 'normal'
      WHEN it.initial_troponin <= 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS category,
    it.initial_troponin
  FROM cohort c
  INNER JOIN initial_trop it
    ON c.hadm_id = it.hadm_id
),
windowed AS (
  SELECT
    category,
    initial_troponin,
    COUNT(*) OVER (PARTITION BY category) AS n,
    COUNT(*) OVER () AS total_n,
    AVG(initial_troponin) OVER (PARTITION BY category) AS mean_troponin,
    PERCENTILE_CONT(0.5) OVER (PARTITION BY category ORDER BY initial_troponin) AS median_troponin,
    PERCENTILE_CONT(0.75) OVER (PARTITION BY category ORDER BY initial_troponin) -
    PERCENTILE_CONT(0.25) OVER (PARTITION BY category ORDER BY initial_troponin) AS iqr_troponin
  FROM categorized
)
SELECT
  category,
  n,
  ROUND(n * 100.0 / total_n, 2) AS percentage,
  ROUND(mean_troponin, 4) AS mean_troponin,
  ROUND(median_troponin, 4) AS median_troponin,
  ROUND(iqr_troponin, 4) AS iqr_troponin
FROM windowed
GROUP BY category, n, total_n, mean_troponin, median_troponin, iqr_troponin
ORDER BY
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    ELSE 3
  END;