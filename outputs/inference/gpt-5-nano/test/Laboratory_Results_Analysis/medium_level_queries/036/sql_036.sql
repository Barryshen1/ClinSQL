WITH ami_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE
    (
      (di.icd_version = 10 AND di.icd_code LIKE 'I21%') OR
      (di.icd_version = 9  AND di.icd_code LIKE '410%')
    )
    AND p.gender = 'M'
    AND NOT (p.anchor_age IS NULL OR p.anchor_year IS NULL)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
),
tn_events AS (
  SELECT
    am.hadm_id,
    am.subject_id,
    le.charttime,
    le.valuenum AS tn_value,
    le.valueuom AS tn_unit
  FROM ami_admissions AS am
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = am.subject_id AND le.hadm_id = am.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON dli.itemid = le.itemid
  WHERE
    LOWER(dli.label) LIKE '%troponin t%' OR LOWER(dli.label) LIKE '%troponin_t%'
),
initial_rn AS (
  SELECT
    hadm_id,
    subject_id,
    charttime,
    tn_value,
    tn_unit,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM tn_events
  WHERE tn_value IS NOT NULL AND tn_unit IS NOT NULL
),
categorized AS (
  SELECT
    hadm_id,
    subject_id,
    charttime,
    tn_value,
    tn_unit,
    CASE
      WHEN LOWER(tn_unit) LIKE '%ng/l%' THEN
        CASE
          WHEN tn_value < 14 THEN 'normal'
          WHEN tn_value < 53 THEN 'borderline'
          ELSE 'myocardial injury'
        END
      WHEN LOWER(tn_unit) LIKE '%ng/ml%' THEN
        CASE
          WHEN (tn_value * 1000) < 14 THEN 'normal'
          WHEN (tn_value * 1000) < 53 THEN 'borderline'
          ELSE 'myocardial injury'
        END
      ELSE NULL
    END AS hs_tn_category,
    rn
  FROM initial_rn
  WHERE rn = 1
),
final_categories AS (
  SELECT hs_tn_category
  FROM categorized
  WHERE hs_tn_category IS NOT NULL
),
agg AS (
  SELECT hs_tn_category, COUNT(*) AS cnt
  FROM final_categories
  GROUP BY hs_tn_category
),
tot AS (
  SELECT SUM(cnt) AS total FROM agg
)
SELECT
  a.hs_tn_category AS hs_tn_category,
  a.cnt AS count,
  ROUND(100.0 * a.cnt / t.total, 1) AS pct
FROM agg AS a
CROSS JOIN tot AS t
ORDER BY hs_tn_category;