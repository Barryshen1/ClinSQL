WITH cohort AS (
  -- Female patients aged 81-91 with chest pain or AMI admissions
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      d.icd_code LIKE '7865%'   -- chest pain
      OR d.icd_code LIKE '410%'  -- AMI
    )
),
index_tn AS (
  -- First (index) troponin measurement per admission
  SELECT
    subject_id,
    hadm_id,
    valuenum AS troponin_value
  FROM (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.charttime,
      le.valuenum,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
      ON le.itemid = di.itemid
    WHERE LOWER(di.label) LIKE '%troponin%'
      AND le.valuenum IS NOT NULL
  )
  WHERE rn = 1
),
combined AS (
  -- Join cohort with their index troponin
  SELECT
    c.hadm_id,
    c.los,
    itn.troponin_value
  FROM cohort AS c
  LEFT JOIN index_tn AS itn
    ON c.hadm_id = itn.hadm_id
  WHERE itn.troponin_value IS NOT NULL   -- only admissions with an hs‐TnT
),
categorized AS (
  -- Categorize troponin values
  SELECT
    hadm_id,
    los,
    CASE
      WHEN troponin_value <= 14 THEN 'normal'
      WHEN troponin_value BETWEEN 15 AND 52 THEN 'borderline'
      WHEN troponin_value >= 53 THEN 'myocardial_injury'
    END AS category
  FROM combined
),
totals AS (
  -- Compute overall total for percentage calculation
  SELECT COUNT(*) AS total_n
  FROM categorized
)
-- Final aggregation
SELECT
  c.category,
  COUNT(*) AS n,
  ROUND(100.0 * COUNT(*) / t.total_n, 1) AS percent,
  ROUND(AVG(c.los), 2) AS mean_los_days
FROM categorized AS c
CROSS JOIN totals AS t
GROUP BY c.category, t.total_n
ORDER BY
  CASE c.category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'myocardial_injury' THEN 3
  END;