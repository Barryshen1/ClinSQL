WITH cohort AS (
  -- Males aged 41-51 (anchor_age is used for age)
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
),
ecg_items AS (
  -- Identify ECG/telemetry items in ICU d_items using case-insensitive matching
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items` di
  WHERE LOWER(COALESCE(di.label, '')) LIKE '%ecg%'
     OR LOWER(COALESCE(di.label, '')) LIKE '%telemetry%'
     OR LOWER(COALESCE(di.category, '')) LIKE '%ecg%'
     OR LOWER(COALESCE(di.category, '')) LIKE '%telemetry%'
),
ecg_counts AS (
  -- Per-subject count of distinct ECG/telemetry itemids observed in ICU chart events
  SELECT c.subject_id,
         COUNT(DISTINCT ce.itemid) AS distinct_ecg_itemids
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = c.subject_id
   AND ce.itemid IN (SELECT itemid FROM ecg_items)
  GROUP BY c.subject_id
),
ordered AS (
  -- Order the per-subject counts to prepare for 75th percentile selection
  SELECT subject_id,
         distinct_ecg_itemids,
         ROW_NUMBER() OVER (ORDER BY distinct_ecg_itemids) AS rn
  FROM ecg_counts
),
n AS (
  SELECT COUNT(*) AS total FROM ecg_counts
)
SELECT DISTINCT ecg_counts.distinct_ecg_itemids AS percentile_75_ecg_distinct_itemids
FROM ordered, n
WHERE ordered.rn = CAST(CEIL(GREATEST(0.75 * n.total, 1)) AS INT64)
LIMIT 1;