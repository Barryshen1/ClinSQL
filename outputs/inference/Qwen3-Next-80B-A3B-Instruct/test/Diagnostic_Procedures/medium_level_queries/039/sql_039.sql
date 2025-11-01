WITH patients_filtered AS (
  SELECT 
    subject_id
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients
  WHERE 
    gender = 'M' 
    AND anchor_age BETWEEN 77 AND 87
),
admissions_filtered AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN 
    patients_filtered p ON a.subject_id = p.subject_id
  WHERE 
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) BETWEEN 1 AND 8
),
icu_status AS (
  SELECT 
    a.hadm_id,  -- Fixed: qualified with alias to resolve ambiguity
    CASE WHEN COUNT(i.stay_id) > 0 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM 
    admissions_filtered a
  LEFT JOIN 
    physionet-data.mimiciv_3_1_icu.icustays i ON a.hadm_id = i.hadm_id
  GROUP BY 
    a.hadm_id
),
imaging_procedures AS (
  -- ICU imaging: procedureevents with CT/MRI
  SELECT 
    p.hadm_id,
    COUNT(*) AS imaging_count
  FROM 
    physionet-data.mimiciv_3_1_icu.procedureevents p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items d ON p.itemid = d.itemid
  WHERE 
    LOWER(d.label) LIKE '%ct%' 
    OR LOWER(d.label) LIKE '%mri%'
  GROUP BY 
    p.hadm_id

  UNION ALL

  -- Non-ICU imaging: hcpcsevents with CT/MRI
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM 
    physionet-data.mimiciv_3_1_hosp.hcpcsevents h
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_hcpcs d ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.short_description) LIKE '%ct%' 
    OR LOWER(d.short_description) LIKE '%mri%'
  GROUP BY 
    h.hadm_id
),
imaging_per_admission AS (
  SELECT 
    hadm_id,
    SUM(imaging_count) AS total_imaging_procedures
  FROM 
    imaging_procedures
  GROUP BY 
    hadm_id
),
final_admissions AS (
  SELECT 
    af.hadm_id,
    af.los_days,
    ic.icu_status,
    COALESCE(ip.total_imaging_procedures, 0) AS imaging_count
  FROM 
    admissions_filtered af
  INNER JOIN 
    icu_status ic ON af.hadm_id = ic.hadm_id
  LEFT JOIN 
    imaging_per_admission ip ON af.hadm_id = ip.hadm_id
),
los_groups AS (
  SELECT 
    icu_status,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    imaging_count
  FROM 
    final_admissions
  WHERE 
    los_days BETWEEN 1 AND 8
)
SELECT 
  icu_status,
  los_group,
  AVG(imaging_count) AS mean_procedures,
  MIN(imaging_count) AS min_procedures,
  MAX(imaging_count) AS max_procedures
FROM 
  los_groups
WHERE 
  los_group IS NOT NULL
GROUP BY 
  icu_status, los_group
ORDER BY 
  icu_status, los_group;