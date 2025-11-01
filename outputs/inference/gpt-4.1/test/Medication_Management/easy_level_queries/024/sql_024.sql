WITH eligible_patients AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
),
aspirin_rx AS (
  SELECT subject_id, hadm_id, starttime, 
    COALESCE(stoptime, dischtime) AS stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  JOIN eligible_patients USING (subject_id, hadm_id)
  WHERE LOWER(drug) LIKE '%aspirin%'
),
p2y12_rx AS (
  SELECT subject_id, hadm_id, starttime, 
    COALESCE(stoptime, dischtime) AS stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  JOIN eligible_patients USING (subject_id, hadm_id)
  WHERE LOWER(drug) LIKE '%clopidogrel%'
     OR LOWER(drug) LIKE '%ticagrelor%'
     OR LOWER(drug) LIKE '%prasugrel%'
),
dapt_overlap AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Overlap start: latest of both starttimes
    GREATEST(a.starttime, p.starttime) AS overlap_start,
    -- Overlap end: earliest of both stoptimes
    LEAST(a.stoptime, p.stoptime) AS overlap_end
  FROM aspirin_rx a
  JOIN p2y12_rx p
    ON a.subject_id = p.subject_id
    AND a.hadm_id = p.hadm_id
    -- Only consider overlapping periods
    AND a.starttime < p.stoptime
    AND p.starttime < a.stoptime
),
dapt_durations AS (
  SELECT
    subject_id,
    hadm_id,
    overlap_start,
    overlap_end,
    -- Duration in days (fractional)
    TIMESTAMP_DIFF(overlap_end, overlap_start, SECOND)/86400.0 AS dapt_days
  FROM dapt_overlap
  WHERE overlap_end > overlap_start
)
SELECT
  MAX(dapt_days) AS max_single_inpatient_dapt_duration_days
FROM dapt_durations;