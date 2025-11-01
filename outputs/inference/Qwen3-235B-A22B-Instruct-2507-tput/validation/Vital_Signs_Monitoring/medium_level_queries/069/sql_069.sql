WITH rr_measurements AS (
  -- Get respiratory rate itemid
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu`.d_items 
  WHERE LOWER(label) = 'respiratory rate'
),
stay_rr_avg AS (
  -- Get average RR in first 48h for each ICU stay
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_rr_48h
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  CROSS JOIN rr_measurements rm
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  WHERE ce.itemid = rm.itemid
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
patients_filtered AS (
  -- Get female patients aged 41-51
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),
stay_with_rr_and_demographics AS (
  -- Link stays with patient filter and get hadm_id for stroke check
  SELECT 
    sra.stay_id,
    sra.avg_rr_48h,
    icu.hadm_id
  FROM stay_rr_avg sra
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON sra.stay_id = icu.stay_id
  INNER JOIN patients_filtered pf
    ON icu.subject_id = pf.subject_id
),
stroke_status AS (
  -- Check if admission had ischemic stroke (ICD-10 I63)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  WHERE di.icd_version = 10
    AND di.icd_code LIKE 'I63%'
),
stay_with_stroke AS (
  SELECT 
    s.stay_id,
    s.avg_rr_48h,
    CASE WHEN ss.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_stroke
  FROM stay_with_rr_and_demographics s
  LEFT JOIN stroke_status ss
    ON s.hadm_id = ss.hadm_id
),
rr_binned AS (
  SELECT 
    stay_id,
    had_stroke,
    CASE
      WHEN avg_rr_48h < 12 THEN '<12'
      WHEN avg_rr_48h BETWEEN 12 AND 20 THEN '12-20'
      WHEN avg_rr_48h BETWEEN 21 AND 29 THEN '21-29'
      WHEN avg_rr_48h >= 30 THEN '>=30'
      ELSE NULL
    END AS rr_bin
  FROM stay_with_stroke
  WHERE avg_rr_48h IS NOT NULL
)
-- Final aggregation: count stays and stroke rate per RR bin
SELECT 
  rr_bin,
  COUNT(*) AS stay_count,
  SUM(had_stroke) AS stroke_count,
  ROUND(SUM(had_stroke) * 100.0 / COUNT(*), 2) AS stroke_rate_percent
FROM rr_binned
WHERE rr_bin IS NOT NULL
GROUP BY rr_bin
ORDER BY 
  CASE rr_bin
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
  END;