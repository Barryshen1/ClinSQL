WITH eligible_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),
antiplatelet_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN eligible_patients ep ON p.subject_id = ep.subject_id
  WHERE LOWER(p.drug) IN (
    'aspirin', 'asa', 'acetylsalicylic acid',
    'clopidogrel',
    'ticagrelor',
    'prasugrel',
    'dipyridamole'
  )
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
),
dapt_pairs AS (
  SELECT 
    p1.hadm_id,
    p1.drug AS drug1,
    p2.drug AS drug2,
    GREATEST(p1.starttime, p2.starttime) AS overlap_start,
    LEAST(p1.stoptime, p2.stoptime) AS overlap_end
  FROM antiplatelet_prescriptions p1
  INNER JOIN antiplatelet_prescriptions p2
    ON p1.hadm_id = p2.hadm_id
    AND p1.drug < p2.drug  -- avoid duplicates and self-joins
    AND p1.starttime < p2.stoptime
    AND p2.starttime < p1.stoptime
),
dapt_durations AS (
  SELECT 
    hadm_id,
    overlap_start,
    overlap_end,
    EXTRACT(DAY FROM (overlap_end - overlap_start)) AS duration_days
  FROM dapt_pairs
  WHERE overlap_end > overlap_start  -- ensure positive duration
)
SELECT 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr
FROM dapt_durations;