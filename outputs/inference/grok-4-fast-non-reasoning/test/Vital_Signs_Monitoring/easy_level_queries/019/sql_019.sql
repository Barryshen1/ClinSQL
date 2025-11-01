WITH qualifying_stays AS (
  -- Get stays in step-down/IMC units for women aged 73-83
  SELECT DISTINCT t.subject_id, t.hadm_id, i.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON p.subject_id = t.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON t.subject_id = i.subject_id AND t.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND (t.careunit LIKE '%Stepdown%' 
         OR t.careunit LIKE '%Intermediate%' 
         OR t.careunit LIKE '%IMCU%' 
         OR t.careunit LIKE '%SDU%')
    AND t.intime < i.outtime  -- Ensure transfer overlaps with ICU stay
),
map_per_stay AS (
  -- Compute average MAP per qualifying stay
  SELECT 
    qs.stay_id,
    AVG(ce.valuenum) AS avg_map_per_stay
  FROM qualifying_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON qs.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.itemid = 220052  -- MAP
    AND di.label = 'Mean Arterial Pressure'  -- Confirm label
    AND ce.valuenum IS NOT NULL
  GROUP BY qs.stay_id
  HAVING avg_map_per_stay IS NOT NULL  -- Only stays with MAP data
)
-- Final average across all qualifying stays
SELECT AVG(avg_map_per_stay) AS cohort_avg_map
FROM map_per_stay;