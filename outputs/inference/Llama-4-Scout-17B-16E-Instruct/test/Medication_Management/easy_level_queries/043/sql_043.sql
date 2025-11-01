WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),
medicated_patients AS (
  SELECT 
    subject_id,
    hadm_id,
    drug
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    drug IN ('hydralazine', 'isosorbide dinitrate')
)
SELECT 
  MIN(DATE_DIFF(DAY, ep.admittime, ep.dischtime)) AS shortest_duration_days
FROM 
  eligible_patients ep
JOIN 
  medicated_patients mp
ON 
  ep.subject_id = mp.subject_id
  AND ep.hadm_id = mp.hadm_id;