WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),
procedure_counts AS (
  SELECT 
    ep.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS distinct_procedures
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON ep.subject_id = pi.subject_id 
    AND ep.hadm_id = pi.hadm_id
  WHERE pi.icd_version = 10
    AND pi.icd_code IN (
      -- Coronary angiography codes
      'B211', 'B211Y', 'B211Z',  -- Coronary arteriography (with/without other vessels)
      'B212', 'B212Y', 'B212Z',  -- Other coronary vessels
      -- PCI / PTCA codes
      'B201', 'B201G', 'B201Y', 'B201Z',  -- Percutaneous transluminal coronary angioplasty (various)
      'B20Z',  -- Coronary angioplasty without stent
      'B202', 'B202G',  -- Insertion of stent(s)
      'B203', 'B203G',  -- Insertion of drug-eluting stent(s)
      -- Additional PCI-related (e.g., atherectomy, balloon)
      'B204', 'B205', 'B206'
    )
  GROUP BY ep.hadm_id
)
SELECT 
  APPROX_QUANTILES(distinct_procedures, 4)[OFFSET(3)] AS p75th_percentile
FROM procedure_counts;