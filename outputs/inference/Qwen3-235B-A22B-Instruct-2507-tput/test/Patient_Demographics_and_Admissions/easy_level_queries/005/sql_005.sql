WITH eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
),
dialysis_patients AS (
  SELECT DISTINCT pe.subject_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.category) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%dialysis%'
),
patients_with_dialysis AS (
  SELECT ep.subject_id
  FROM eligible_patients ep
  INNER JOIN dialysis_patients dp
    ON ep.subject_id = dp.subject_id
),
first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.los AS icu_los_days,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN patients_with_dialysis p
    ON i.subject_id = p.subject_id
),
first_stay_filtered AS (
  SELECT icu_los_days
  FROM first_icu_stay
  WHERE rn = 1
)
SELECT
  APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(750)] -
  APPROX_QUANTILES(icu_los_days, 1000)[OFFSET(250)] AS iqr_icu_los_days
FROM first_stay_filtered;