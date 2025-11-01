WITH chest_pain_admits AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) IN ('f', 'female')
    AND p.anchor_age BETWEEN 87 AND 97
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
      WHERE diag.subject_id = a.subject_id
        AND diag.hadm_id = a.hadm_id
        AND (
          (diag.icd_version = 9  AND diag.icd_code LIKE '786.5%') OR
          (diag.icd_version = 10 AND diag.icd_code LIKE 'R07.9%')
        )
    )
),
index_hstnt AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    l.charttime,
    l.valuenum AS tnt_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  JOIN chest_pain_admits AS a
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE (
        LOWER(d.label) LIKE '%troponin%'
        OR LOWER(d.label) LIKE '%hs-troponin%'
        OR LOWER(d.label) LIKE '%troponin t%'
        OR LOWER(d.label) LIKE '%high-sensitivity%'
      )
    AND l.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id, a.hadm_id ORDER BY l.charttime) = 1
),
index_by_category AS (
  SELECT
    CASE
      WHEN tnt_value <= 0.04 THEN 'Normal'
      WHEN tnt_value <= 0.1  THEN 'Borderline'
      ELSE 'Injury'
    END AS category,
    tnt_value
  FROM index_hstnt
  WHERE tnt_value IS NOT NULL
),
summary AS (
  SELECT
    category,
    COUNT(*) AS n,
    100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS pct,
    AVG(tnt_value) AS mean_value,
    -- Approximate median using 50th percentile from 100 quantiles
    APPROX_QUANTILES(tnt_value, 100)[OFFSET(50)] AS median_value,
    -- Precompute quantiles for IQR (75th and 25th percentiles)
    APPROX_QUANTILES(tnt_value, 100) AS q
  FROM index_by_category
  GROUP BY category
)
SELECT
  category,
  n AS count,
  ROUND(pct, 2) AS percent,
  ROUND(mean_value, 4) AS mean_value,
  median_value AS median_value,
  (q[OFFSET(75)] - q[OFFSET(25)]) AS iqr_approx
FROM summary
ORDER BY category;