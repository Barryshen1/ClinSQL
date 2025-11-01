WITH spo2_items AS (
  -- Find likely SpO2 / oxygen saturation itemids
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
     OR LOWER(label) LIKE '%o2 sat%'
     OR LOWER(label) LIKE '%oxygen saturation%'
     OR LOWER(abbreviation) LIKE '%spo2%'
     OR LOWER(label) LIKE '%pulse oximetry%'
),

per_stay_avg AS (
  -- Compute per-ICU-stay average SpO2 in the first 24 hours
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    AVG(ce.valuenum) AS avg_spo2,
    COUNT(ce.valuenum) AS n_meas
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = s.subject_id
   AND ce.hadm_id = s.hadm_id
   AND ce.stay_id = s.stay_id
  JOIN spo2_items i
    ON ce.itemid = i.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND ce.charttime >= s.intime
    AND ce.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 50 AND 100  -- plausible SpO2 bounds
  GROUP BY s.subject_id, s.hadm_id, s.stay_id, s.intime
  HAVING COUNT(ce.valuenum) > 0
)

SELECT
  COUNT(*) AS total_stays_included,
  SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) AS stays_with_avg_spo2_le_88,
  ROUND(
    100.0 * SUM(CASE WHEN avg_spo2 <= 88 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS percentile_of_88_pct  -- percentile (0-100) defined as % of stays with avg_spo2 <= 88
FROM per_stay_avg;