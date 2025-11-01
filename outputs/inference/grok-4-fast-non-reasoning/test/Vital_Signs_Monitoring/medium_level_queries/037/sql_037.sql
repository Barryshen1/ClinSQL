WITH gcs_scores AS (
  SELECT DISTINCT 
    ce.stay_id,
    ce.valuenum AS gcs_total
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id 
    AND ce.hadm_id = icu.hadm_id 
    AND ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE ce.itemid = 198  -- GCS Total
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND icu.intime <= ce.charttime 
    AND ce.charttime <= icu.outtime
    AND DATE_DIFF(DATE(ce.charttime), DATE(icu.intime), DAY) + 1 >= 2  -- ICU day 2 or later
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` hf
      WHERE hf.subject_id = icu.subject_id
        AND hf.hadm_id = icu.hadm_id
        AND hf.stay_id = icu.stay_id
        AND hf.itemid = 228543  -- Ventilator Type
        AND hf.value = 'High Flow'  -- High-flow nasal cannula
        AND icu.intime <= hf.charttime 
        AND hf.charttime <= icu.outtime
    )
)

SELECT 
  COUNT(*) AS num_patients_stays_with_gcs,
  PERCENTILE_CONT(0.5, gcs_total) OVER() AS median_gcs_total
FROM gcs_scores;