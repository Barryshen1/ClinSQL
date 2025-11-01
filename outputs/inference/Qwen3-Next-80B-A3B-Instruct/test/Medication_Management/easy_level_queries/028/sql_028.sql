WITH antiplatelet_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM 
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients pt 
    ON p.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 44 AND 54
    AND p.stoptime IS NOT NULL
    AND LOWER(p.drug) IN (
      'aspirin', 'acetylsalicylic acid', 'clopidogrel', 'ticagrelor', 
      'prasugrel', 'dipyridamole', 'cilostazol', 
      'eptifibatide', 'tirofiban', 'abciximab'
    )
),
dapt_patients AS (
  SELECT DISTINCT
    ap1.subject_id,
    ap1.hadm_id
  FROM 
    antiplatelet_prescriptions ap1
  INNER JOIN 
    antiplatelet_prescriptions ap2
    ON ap1.subject_id = ap2.subject_id
    AND ap1.hadm_id = ap2.hadm_id
    AND ap1.drug < ap2.drug  -- avoid self-join duplicates and ensure distinct drugs
    AND ap1.starttime <= ap2.stoptime
    AND ap2.starttime <= ap1.stoptime  -- overlapping time windows
)
SELECT 
  STDDEV(TIMESTAMP_DIFF(ap.stoptime, ap.starttime, DAY)) AS sd_single_antiplatlet_duration_days
FROM 
  antiplatelet_prescriptions ap
INNER JOIN 
  dapt_patients dp
  ON ap.subject_id = dp.subject_id
  AND ap.hadm_id = dp.hadm_id;