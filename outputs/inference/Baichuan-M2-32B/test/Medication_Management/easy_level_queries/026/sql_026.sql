WITH prescriptions_filtered AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 81 AND 91
    AND p.hadm_id IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND p.drug IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(p.drug), r'amlodipine|nifedipine|felodipine|nicardipine|isradipine|cinnarizine|nimodipine')
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS p25_duration
FROM prescriptions_filtered;