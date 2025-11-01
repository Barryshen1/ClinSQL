WITH tia_admissions AS (
  -- admissions with a TIA diagnosis (ICD-9 435* or ICD-10 G45* or long_title contains transient ischemic/ischemic attack)
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON dx.icd_code = d.icd_code
    AND dx.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      -- ICD code patterns
      dx.icd_code LIKE 'G45%' OR dx.icd_code LIKE '435%'
      -- or descriptive match on diagnosis long title
      OR LOWER(COALESCE(d.long_title, '')) LIKE '%transient isch%'
      OR LOWER(COALESCE(d.long_title, '')) LIKE '%transient ischemic attack%'
    )
),
los_grouped AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    -- LOS in whole days (date difference); exclude nulls
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS los_days
  FROM tia_admissions
  WHERE admittime IS NOT NULL AND dischtime IS NOT NULL
    AND DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) BETWEEN 1 AND 7
),
hcpcs_ct_mri AS (
  -- Count HCPCS events that look like CT/MRI per admission
  SELECT
    h.hadm_id,
    COUNT(1) AS hcpcs_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE (
    LOWER(COALESCE(dh.long_description, '')) LIKE '%computed tomography%' OR
    LOWER(COALESCE(dh.long_description, '')) LIKE '%magnetic resonance%' OR
    LOWER(COALESCE(dh.long_description, '')) LIKE '%mri%' OR
    LOWER(COALESCE(dh.long_description, '')) LIKE '%ct%' OR
    LOWER(COALESCE(h.short_description, '')) LIKE '%computed tomography%' OR
    LOWER(COALESCE(h.short_description, '')) LIKE '%magnetic resonance%' OR
    LOWER(COALESCE(h.short_description, '')) LIKE '%mri%' OR
    LOWER(COALESCE(h.short_description, '')) LIKE '%ct%'
  )
  GROUP BY h.hadm_id
),
procedures_icd_ct_mri AS (
  -- Count ICD-coded procedures that look like CT/MRI per admission
  SELECT
    p.hadm_id,
    COUNT(1) AS icd_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
  WHERE (
    LOWER(COALESCE(dp.long_title, '')) LIKE '%computed tomography%' OR
    LOWER(COALESCE(dp.long_title, '')) LIKE '%magnetic resonance%' OR
    LOWER(COALESCE(dp.long_title, '')) LIKE '%mri%' OR
    LOWER(COALESCE(dp.long_title, '')) LIKE '%ct%'
  )
  GROUP BY p.hadm_id
),
ct_mri_counts AS (
  -- Sum counts from both sources per admission
  SELECT
    lg.hadm_id,
    COALESCE(hc.hcpcs_count, 0) + COALESCE(ic.icd_proc_count, 0) AS procedures_count,
    lg.subject_id,
    lg.los_days
  FROM los_grouped lg
  LEFT JOIN hcpcs_ct_mri hc ON lg.hadm_id = hc.hadm_id
  LEFT JOIN procedures_icd_ct_mri ic ON lg.hadm_id = ic.hadm_id
),
final_prep AS (
  SELECT
    hadm_id,
    subject_id,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE 'other'
    END AS los_group,
    procedures_count
  FROM ct_mri_counts
)
SELECT
  los_group AS los_range,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(1) AS admission_count,
  ROUND(AVG(procedures_count), 3) AS mean_ct_mri_procedures_per_admission
FROM final_prep
WHERE los_group IN ('1-3', '4-7')
GROUP BY los_group
ORDER BY los_group;