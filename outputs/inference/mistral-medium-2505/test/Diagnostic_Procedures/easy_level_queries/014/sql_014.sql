WITH
-- Get mechanical circulatory support device itemids from d_items
circulatory_support_devices AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%IABP%'
     OR label LIKE '%Impella%'
     OR label LIKE '%ECMO%'
     OR label LIKE '%VAD%'
     OR label LIKE '%LVAD%'
     OR label LIKE '%RVAD%'
     OR label LIKE '%Balloon Pump%'
),

-- Get hospitalizations for males aged 73-83
eligible_hospitalizations AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),

-- Count distinct circulatory support devices per hospitalization
device_counts AS (
  SELECT
    e.hadm_id,
    COUNT(DISTINCT p.itemid) AS distinct_device_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN eligible_hospitalizations e ON p.hadm_id = e.hadm_id
  JOIN circulatory_support_devices c ON p.itemid = c.itemid
  GROUP BY e.hadm_id
)

-- Calculate the median number of distinct devices per hospitalization
SELECT
  PERCENTILE_CONT(device_counts.distinct_device_count, 0.5) OVER() AS median_distinct_devices
FROM device_counts
LIMIT 1;