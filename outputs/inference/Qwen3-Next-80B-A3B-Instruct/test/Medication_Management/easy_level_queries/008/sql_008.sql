WITH qualifying_patients AS (
  SELECT DISTINCT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
    AND pt.anchor_age BETWEEN 64 AND 74
    AND LOWER(p.drug) IN (
      'aspirin', 'acetylsalicylic acid', 'asa', 'acetylsalicylate',
      'aspirin, enteric coated', 'aspirin, extended release'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p2
      WHERE p2.hadm_id = p.hadm_id
        AND LOWER(p2.drug) IN (
          'clopidogrel', 'ticagrelor', 'prasugrel', 'ticlopidine'
        )
    )
),
antiplatelet_prescriptions AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.stoptime,
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN qualifying_patients qp ON p.hadm_id = qp.hadm_id
  WHERE LOWER(p.drug) IN (
    'aspirin', 'acetylsalicylic acid', 'asa', 'acetylsalicylate',
    'aspirin, enteric coated', 'aspirin, extended release',
    'clopidogrel', 'ticagrelor', 'prasugrel', 'ticlopidine'
  )
    AND p.stoptime IS NOT NULL
)
SELECT DISTINCT PERCENTILE_CONT(duration_days, 0.5) OVER() AS median_duration_days
FROM antiplatelet_prescriptions;