WITH qualifying_adms AS (
  SELECT 
    a.subject_id, 
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND 75 <= p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year 
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year <= 85
),
proc_candidates AS (
  SELECT 
    proc.subject_id, 
    proc.hadm_id, 
    d.long_title
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON proc.icd_code = d.icd_code 
    AND proc.icd_version = d.icd_version
),
relevant_procs AS (
  SELECT 
    pc.subject_id
  FROM 
    proc_candidates pc
  JOIN 
    qualifying_adms qa 
    ON pc.subject_id = qa.subject_id 
    AND pc.hadm_id = qa.hadm_id
  WHERE 
    (
      (pc.long_title LIKE '%ablation%' 
       AND (pc.long_title LIKE '%heart%' 
            OR pc.long_title LIKE '%cardiac%' 
            OR pc.long_title LIKE '%cardio%'))
    )
    OR
    (
      pc.long_title LIKE '%cardioversion%' 
      OR 
      (pc.long_title LIKE '%conversion%' 
       AND pc.long_title LIKE '%rhythm%' 
       AND (pc.long_title LIKE '%heart%' 
            OR pc.long_title LIKE '%cardiac%' 
            OR pc.long_title LIKE '%cardio%'))
    )
),
qualifying_patients AS (
  SELECT DISTINCT 
    subject_id
  FROM 
    qualifying_adms
),
patient_procs AS (
  SELECT 
    qp.subject_id, 
    COUNT(rp.subject_id) AS num_procs
  FROM 
    qualifying_patients qp
  LEFT JOIN 
    relevant_procs rp 
    ON qp.subject_id = rp.subject_id
  GROUP BY 
    qp.subject_id
),
agg AS (
  SELECT 
    APPROX_QUANTILES(num_procs, 4) AS quantiles
  FROM 
    patient_procs
)
SELECT 
  quantiles[OFFSET(1)] AS Q1,
  quantiles[OFFSET(3)] AS Q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS IQR
FROM 
  agg;