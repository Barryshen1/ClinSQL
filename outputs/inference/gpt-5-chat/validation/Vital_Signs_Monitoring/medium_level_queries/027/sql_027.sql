WITH heart_rate_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
    AND linksto = 'chartevents'
),
female_elderly_stays AS (
  SELECT icu.subject_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
),
avg_hr_per_stay AS (
  SELECT 
    fes.subject_id,
    fes.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM female_elderly_stays fes
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fes.subject_id = ce.subject_id
    AND fes.stay_id = ce.stay_id
  JOIN heart_rate_item hri
    ON ce.itemid = hri.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY fes.subject_id, fes.stay_id
),
distribution AS (
  SELECT 
    COUNTIF(avg_hr <= 110) AS num_leq_110,
    COUNT(*) AS total_stays
  FROM avg_hr_per_stay
)
SELECT 
  num_leq_110 / total_stays * 100 AS percentile_for_110_bpm
FROM distribution;