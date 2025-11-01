WITH hf_stays AS (
  SELECT DISTINCT ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ie.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%high-flow%' 
     OR LOWER(di.label) LIKE '%high flow%'
     OR LOWER(di.label) LIKE '%hfnc%'
),
sbp_items AS (
  SELECT ce.stay_id, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%systolic%' AND LOWER(di.label) LIKE '%blood%'
)
SELECT MIN(mean_sbp) AS min_per_stay_mean_sbp
FROM (
  SELECT icu.stay_id, AVG(sb.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
  JOIN sbp_items AS sb
    ON icu.stay_id = sb.stay_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND icu.stay_id IN (SELECT stay_id FROM hf_stays)
    AND sb.valuenum IS NOT NULL
    AND sb.stay_id = icu.stay_id
    -- Ensure SBP measurements occurred during the ICU stay
    AND sb.charttime BETWEEN icu.intime AND icu.outtime
  GROUP BY icu.stay_id
) AS per_stay;