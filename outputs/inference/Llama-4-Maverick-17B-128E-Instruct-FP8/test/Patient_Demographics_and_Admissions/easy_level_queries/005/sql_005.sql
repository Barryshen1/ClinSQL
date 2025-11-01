WITH dialysis_patients AS (
  SELECT DISTINCT pe.subject_id, pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON p.subject_id = pe.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON pe.subject_id = a.subject_id AND pe.hadm_id = a.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 77 AND 87
  AND pe.itemid = 225441  -- Assuming 225441 is the correct itemid for dialysis
),
first_icu_stay AS (
  SELECT subject_id, hadm_id, stay_id, intime, outtime,
  ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS icu_stay_num
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT 
  APPROX_QUANTILES(DATE_DIFF(outtime, intime, DAY), 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(DATE_DIFF(outtime, intime, DAY), 100)[OFFSET(75)] AS q3
FROM first_icu_stay
WHERE hadm_id IN (SELECT hadm_id FROM dialysis_patients) 
  AND icu_stay_num = 1;