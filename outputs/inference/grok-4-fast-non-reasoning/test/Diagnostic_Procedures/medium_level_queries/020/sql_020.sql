WITH tia_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN COUNT(i.stay_id) OVER (PARTITION BY a.hadm_id) > 0 THEN 'Yes' ELSE 'No' END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND (d.icd_code = 'G45.9' OR d.icd_code LIKE 'I69.32%')  -- TIA codes (ICD-9/10)
    AND icd.long_title LIKE '%transient ischemic attack%'  -- Ensure TIA specificity
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7  -- LOS 1-7 days
),
imaging_procs AS (
  SELECT 
    ta.subject_id,
    ta.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS imaging_count
  FROM tia_admissions ta
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
    ON ta.subject_id = pr.subject_id AND ta.hadm_id = pr.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc 
    ON pr.icd_code = dproc.icd_code AND pr.icd_version = dproc.icd_version
  WHERE pr.icd_code LIKE '87.%'  -- Diagnostic imaging procedures (CT, MRI, X-ray, etc.)
    AND dproc.long_title LIKE '%diagnostic%'  -- Focus on diagnostic (exclude interventional)
  GROUP BY ta.subject_id, ta.hadm_id
)
SELECT 
  CASE 
    WHEN ta.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ta.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_bin,
  ta.icu_use,
  COUNT(DISTINCT ta.hadm_id) AS admission_count,
  AVG(COALESCE(ip.imaging_count, 0)) AS mean_imaging_procs_per_admission
FROM tia_admissions ta
LEFT JOIN imaging_procs ip 
  ON ta.subject_id = ip.subject_id AND ta.hadm_id = ip.hadm_id
GROUP BY los_bin, ta.icu_use
ORDER BY los_bin, ta.icu_use;