WITH male_icu_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
  GROUP BY p.subject_id
),
arterial_pH AS (
  SELECT 
    c.subject_id,
    c.valuenum AS ph_value
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents c
  INNER JOIN male_icu_patients m
    ON c.subject_id = m.subject_id
  WHERE c.itemid = 220274  -- Confirmed arterial pH in d_items
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 0 AND 14  -- Valid pH range
),
peak_pH_per_patient AS (
  SELECT 
    subject_id,
    MAX(ph_value) AS peak_pH  -- Peak = highest pH value
  FROM arterial_pH
  GROUP BY subject_id
)
SELECT 
  APPROX_QUANTILES(peak_pH, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(peak_pH, 1000)[OFFSET(250)] AS iqr
FROM peak_pH_per_patient;