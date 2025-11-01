WITH target AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 62 AND 72
),

-- 2) Gather all SpO2-related chart events from the ICU dataset for those subjects
spo2_candidates AS (
  SELECT ce.subject_id,
         ce.charttime,
         ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%spo2%'
    AND ce.subject_id IN (SELECT subject_id FROM target)
),

-- 3) For each subject, identify the first SpO2 charttime
first_spo2 AS (
  SELECT subject_id, MIN(charttime) AS first_charttime
  FROM spo2_candidates
  GROUP BY subject_id
),

-- 4) Get the SpO2 value corresponding to the first charttime per subject
spo2_firsts AS (
  SELECT DISTINCT f.subject_id,
                  sc.valuenum AS spo2_first
  FROM first_spo2 f
  JOIN spo2_candidates sc
    ON sc.subject_id = f.subject_id
   AND sc.charttime = f.first_charttime
)

-- 5) Compute the IQR: Q3 - Q1 using approximate quantiles
SELECT
  (q[OFFSET(3)] - q[OFFSET(1)]) AS iqr_spo2
FROM (
  SELECT APPROX_QUANTILES(spo2_first, 4) AS q
  FROM spo2_firsts
) t;