WITH
-- 1) Base AP male population aged ~63-73
base_pop AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id AND di.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND LOWER(dd.long_title) LIKE '%pancreatitis%'
),
-- 2) Abnormal lab observations per admission-item within 72h
lab_abn_by_hadm_item AS (
  SELECT
    b.hadm_id,
    le.itemid,
    MAX(
      CASE
        WHEN le.valuenum IS NOT NULL
             AND le.ref_range_lower IS NOT NULL
             AND le.ref_range_upper IS NOT NULL
             AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
        THEN 1
        ELSE 0
      END
    ) AS abnormal
  FROM base_pop AS b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = b.hadm_id
   AND le.subject_id = b.subject_id
   AND le.charttime >= b.admittime
   AND le.charttime < TIMESTAMP_ADD(b.admittime, INTERVAL 72 HOUR)
  GROUP BY b.hadm_id, le.itemid
),
-- 3) Coalesce NULLs to 0 (no labs -> 0 abnormal)
lab_abn_by_hadm_item_coalesced AS (
  SELECT hadm_id, itemid, COALESCE(abnormal, 0) AS abnormal
  FROM lab_abn_by_hadm_item
),
-- 4) Instability per admission (sum of abnormal across items in 72h)
inst_per_hadm AS (
  SELECT hadm_id, SUM(abnormal) AS instability72
  FROM lab_abn_by_hadm_item_coalesced
  GROUP BY hadm_id
),
-- 5) Ensure every base_pop admission has an instability72 value (0 if no labs)
inst_full AS (
  SELECT b.hadm_id, COALESCE(i.instability72, 0) AS instability72
  FROM base_pop AS b
  LEFT JOIN inst_per_hadm AS i
    ON b.hadm_id = i.hadm_id
),
-- 6) 90th percentile cutoff using APPROX_QUANTILES (computed in a subquery to satisfy BigQuery rules)
p90 AS (
  SELECT quant AS p90
  FROM (
    SELECT APPROX_QUANTILES(instability72, 100) AS q
    FROM inst_full
  ) AS t
  CROSS JOIN UNNEST(t.q) AS quant WITH OFFSET AS idx
  WHERE idx = 90
  LIMIT 1
),
-- 7) Define top90 vs other admissions
top90_hadm AS (
  SELECT i.hadm_id
  FROM inst_full i
  CROSS JOIN p90
  WHERE i.instability72 >= p90.p90
),
other_hadm AS (
  SELECT i.hadm_id
  FROM inst_full i
  CROSS JOIN p90
  WHERE i.instability72 < p90.p90
),
-- 8) Top90 lab rates by item
top90_lab_rates AS (
  SELECT di.itemid, di.label, AVG(lab.abnormal) AS top90_rate
  FROM lab_abn_by_hadm_item_coalesced lab
  JOIN top90_hadm th ON lab.hadm_id = th.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON lab.itemid = di.itemid
  GROUP BY di.itemid, di.label
),
-- 9) General (other) lab rates by item
general_lab_rates AS (
  SELECT di.itemid, di.label, AVG(lab.abnormal) AS general_rate
  FROM lab_abn_by_hadm_item_coalesced lab
  JOIN other_hadm oh ON lab.hadm_id = oh.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON lab.itemid = di.itemid
  GROUP BY di.itemid, di.label
)

-- Output:
-- 1) Mortality for top90
SELECT
  'mortality_top90' AS metric_label,
  AVG(CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1.0 ELSE 0.0 END) AS value,
  NULL AS top90_rate,
  NULL AS general_rate,
  NULL AS lab_label
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN top90_hadm AS th
  ON a.hadm_id = th.hadm_id

UNION ALL

-- 2) Mean LOS (top90)
SELECT
  'mean_los_days' AS metric_label,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS value,
  NULL AS top90_rate,
  NULL AS general_rate,
  NULL AS lab_label
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN top90_hadm AS th
  ON a.hadm_id = th.hadm_id
WHERE a.dischtime IS NOT NULL

UNION ALL

-- 3) Per-lab rates: top90 vs general
SELECT
  NULL AS metric_label,
  NULL AS value,
  tb.top90_rate AS top90_rate,
  gb.general_rate AS general_rate,
  di.label AS lab_label
FROM top90_lab_rates tb
JOIN general_lab_rates gb ON tb.itemid = gb.itemid
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
  ON tb.itemid = di.itemid
ORDER BY lab_label;