WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
icu_admissions AS (
  SELECT ie.subject_id, ie.hadm_id, ie.stay_id, ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN male_patients p ON ie.subject_id = p.subject_id
),
first_sodium AS (
  SELECT ia.subject_id, ia.hadm_id, ia.stay_id,
         le.valuenum AS sodium_value,
         ROW_NUMBER() OVER (PARTITION BY ia.stay_id ORDER BY le.charttime) AS rn
  FROM icu_admissions ia
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON ia.hadm_id = le.hadm_id
  WHERE le.itemid = (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label LIKE '%Sodium%' AND label LIKE '%Serum%' LIMIT 1)
)
SELECT 
  APPROX_QUANTILES(sodium_value, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(sodium_value, 100)[OFFSET(75)] AS q3
FROM first_sodium
WHERE rn = 1;