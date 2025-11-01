WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    p.gender,
    p.anchor_age,
    LOS
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  CROSS JOIN (
    SELECT 
      DATE_DIFF(a.dischtime, a.admittime, DAY) AS LOS
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    WHERE 
      a.hadm_id = a.hadm_id  -- Self-reference for LOS calc
  ) los_calc
  WHERE 
    p.gender = 'F'
    AND p.anchor_age = 74
    AND d.icd_code LIKE 'I50%'
    AND LOS BETWEEN 1 AND 7
),
diagnostics AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    h.hcpcs_cd,
    dh.short_description
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE 
    LOWER(dh.short_description) LIKE '%x-ray%'
    OR LOWER(dh.short_description) LIKE '%ct scan%'
    OR LOWER(dh.short_description) LIKE '%mri%'
    OR LOWER(dh.short_description) LIKE '%ultrasound%'
    OR LOWER(dh.short_description) LIKE '%echocardiography%'
    OR LOWER(dh.short_description) LIKE '%ecg%'
    OR LOWER(dh.short_description) LIKE '%ekg%'
    OR LOWER(dh.short_description) LIKE '%eeg%'
    OR LOWER(dh.short_description) LIKE '%pulmonary function%'
    OR LOWER(dh.short_description) LIKE '%pft%'
),
stratified_counts AS (
  SELECT 
    CASE 
      WHEN c.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent'
      ELSE 'Elective'
    END AS admission_type_group,
    CASE 
      WHEN c.LOS BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN c.LOS BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    COUNT(DISTINCT d.hcpcs_cd) AS num_diagnostics
  FROM 
    cohort c
  LEFT JOIN 
    diagnostics d
    ON c.hadm_id = d.hadm_id
  GROUP BY 
    c.hadm_id, admission_type_group, los_group
)
SELECT 
  admission_type_group,
  los_group,
  ROUND(AVG(num_diagnostics), 2) AS mean_diagnostics_per_admission,
  COUNT(*) AS num_admissions
FROM 
  stratified_counts
GROUP BY 
  admission_type_group, los_group
ORDER BY 
  admission_type_group, los_group;