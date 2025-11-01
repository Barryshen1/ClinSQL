WITH troponin_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE le.valuenum IS NOT NULL
    -- Attempt to capture hs-Troponin T measurements; adjust as needed based on labitem labels
    AND (LOWER(dli.label) LIKE '%troponin%')
    AND (LOWER(dli.label) LIKE '%troponin t%' OR LOWER(dli.label) LIKE '%hs%troponin%')
),
ranked AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.charttime,
    t.valuenum,
    ROW_NUMBER() OVER (PARTITION BY t.subject_id ORDER BY t.charttime) AS rn
  FROM troponin_events AS t
),
first_measure AS (
  SELECT *
  FROM ranked
  WHERE rn = 1
)
SELECT
  CASE
    WHEN fm.valuenum < 0.014 THEN 'Normal (<0.014)'
    WHEN fm.valuenum >= 0.014 AND fm.valuenum < 0.04 THEN 'Borderline (0.014–<0.04)'
    WHEN fm.valuenum >= 0.04 THEN 'Myocardial Injury (≥0.04)'
    ELSE 'Unknown'
  END AS category,
  COUNT(DISTINCT fm.subject_id) AS patient_count
FROM first_measure fm
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON a.hadm_id = fm.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON p.subject_id = fm.subject_id
WHERE LOWER(p.gender) IN ('f', 'female')
  AND (p.anchor_age IS NOT NULL AND p.anchor_year IS NOT NULL)
  -- age at admission
  AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 42 AND 52
  AND fm.valuenum IS NOT NULL
GROUP BY category
ORDER BY category;