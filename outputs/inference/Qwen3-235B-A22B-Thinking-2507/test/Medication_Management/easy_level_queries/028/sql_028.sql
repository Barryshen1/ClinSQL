WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 44 AND 54
),
prescriptions_antiplatelet AS (
  SELECT
    p.hadm_id,
    p.starttime,
    p.stoptime,
    -- Flag aspirin-class drugs
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'aspirin|acetylsalicylic acid|asa') 
      THEN 1 ELSE 0 
    END AS is_aspirin,
    -- Flag P2Y12 inhibitors
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'clopidogrel|prasugrel|ticagrelor') 
      THEN 1 ELSE 0 
    END AS is_p2y12
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE p.starttime IS NOT NULL 
    AND p.stoptime IS NOT NULL
),
dapt_patients AS (
  SELECT 
    hadm_id
  FROM prescriptions_antiplatelet
  GROUP BY hadm_id
  HAVING SUM(is_aspirin) > 0 AND SUM(is_p2y12) > 0
),
dapt_antiplatelet_durations AS (
  SELECT
    p.hadm_id,
    -- Calculate duration in fractional days (avoiding date truncation)
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / (24 * 60 * 60) AS duration_days
  FROM prescriptions_antiplatelet p
  INNER JOIN dapt_patients d ON p.hadm_id = d.hadm_id
  INNER JOIN admissions_filtered a ON p.hadm_id = a.hadm_id
  WHERE (p.is_aspirin = 1 OR p.is_p2y12 = 1)
    AND p.stoptime >= p.starttime  -- Exclude negative durations
)
SELECT
  STDDEV(duration_days) AS sd_duration_days
FROM dapt_antiplatelet_durations;