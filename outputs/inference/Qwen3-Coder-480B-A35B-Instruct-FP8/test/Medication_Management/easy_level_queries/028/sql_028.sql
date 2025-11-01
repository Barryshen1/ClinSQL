WITH dapt_patients AS (
  -- Identify patients on DAPT (admitted, female, age 44–54)
  SELECT DISTINCT p.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr1
      WHERE pr1.hadm_id = a.hadm_id
        AND LOWER(pr1.drug) LIKE '%aspirin%'
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr2
      WHERE pr2.hadm_id = a.hadm_id
        AND LOWER(pr2.drug) LIKE '%clopidogrel%'
    )
),
single_antiplatelet_rx AS (
  -- Get single antiplatelet prescriptions for DAPT patients
  SELECT
    pr.hadm_id,
    pr.subject_id,
    pr.drug,
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr
  JOIN dapt_patients dp ON pr.subject_id = dp.subject_id
  WHERE LOWER(pr.drug) IN ('aspirin', 'clopidogrel', 'prasugrel', 'ticagrelor')
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime >= pr.starttime
)
-- Compute standard deviation of durations
SELECT
  STDDEV(duration_hours) AS stddev_single_antiplatelet_duration_hours
FROM single_antiplatelet_rx;