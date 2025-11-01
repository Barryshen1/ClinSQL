WITH male_icu_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
arterial_pH_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%pH%' 
    AND LOWER(label) LIKE '%arterial%'
    AND linksto = 'chartevents'
),
peak_pH_per_patient AS (
  SELECT 
    c.subject_id,
    MAX(c.valuenum) AS peak_pH
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN male_icu_patients mip
    ON c.subject_id = mip.subject_id
  JOIN arterial_pH_items api
    ON c.itemid = api.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 6.8 AND 7.8  -- Physiological range
  GROUP BY c.subject_id
)
SELECT DISTINCT
  PERCENTILE_CONT(peak_pH, 0.75) OVER() - PERCENTILE_CONT(peak_pH, 0.25) OVER() AS iqr_peak_pH
FROM peak_pH_per_patient
WHERE peak_pH IS NOT NULL;