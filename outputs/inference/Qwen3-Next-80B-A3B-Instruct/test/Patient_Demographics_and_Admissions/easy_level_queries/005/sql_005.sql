WITH dialysis_patients AS (
  SELECT DISTINCT p.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON p.subject_id = pe.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND LOWER(di.label) LIKE '%dialysis%'
),
first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN dialysis_patients dp
    ON i.subject_id = dp.subject_id
)
SELECT 
  PERCENTILE_CONT(los, 0.25) OVER () AS q1,
  PERCENTILE_CONT(los, 0.75) OVER () AS q3,
  PERCENTILE_CONT(los, 0.75) OVER () - PERCENTILE_CONT(los, 0.25) OVER () AS iqr
FROM first_icu_stay
WHERE rn = 1
LIMIT 1;