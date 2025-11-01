WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
  AND anchor_age = 63  -- Adding age filter as per the clinical question context
),
male_icu_stays AS (
  SELECT i.stay_id, i.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN male_patients p ON i.subject_id = p.subject_id
),
peak_ph AS (
  SELECT MAX(c.valuenum) AS peak_ph
  FROM male_icu_stays m
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON m.stay_id = c.stay_id
  WHERE c.itemid = 50820  
  GROUP BY m.subject_id
)
SELECT 
  APPROX_QUANTILES(peak_ph.peak_ph, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(peak_ph.peak_ph, 100)[OFFSET(75)] AS q3
FROM peak_ph;