WITH aki_definitions AS (
  SELECT 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '584%') OR 
    (icd_version = 10 AND icd_code LIKE 'N17%')
),
aki_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Calculate age at admission using MIMIC-IV standard formula
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Determine if primary or secondary AKI
    CASE 
      WHEN primary_diag.hadm_id IS NOT NULL THEN 'primary'
      ELSE 'secondary'
    END AS aki_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Get admissions with primary AKI diagnosis (seq_num = 1)
  LEFT JOIN (
    SELECT 
      diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN aki_definitions ad
      ON diag.icd_code = ad.icd_code AND diag.icd_version = ad.icd_version
    WHERE diag.seq_num = 1
  ) primary_diag ON a.hadm_id = primary_diag.hadm_id
  -- Only include patients with any AKI diagnosis
  INNER JOIN (
    SELECT 
      diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN aki_definitions ad
      ON diag.icd_code = ad.icd_code AND diag.icd_version = ad.icd_version
    GROUP BY diag.hadm_id
  ) any_diag ON a.hadm_id = any_diag.hadm_id
  WHERE 
    -- Filter for male patients aged 43-53
    p.gender = 'M' AND
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
),
los_calculation AS (
  SELECT
    hadm_id,
    -- Calculate hospital LOS in days precisely
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60) AS hospital_los,
    CASE
      WHEN TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60) BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE dischtime IS NOT NULL AND admittime IS NOT NULL
),
imaging_counts AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS mri_ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    -- Comprehensive regex for MRI/CT procedures
    REGEXP_CONTAINS(LOWER(d.long_description), r'computerized tomography|ct scan|magnetic resonance imaging|mri') OR
    REGEXP_CONTAINS(LOWER(d.short_description), r'computerized tomography|ct scan|magnetic resonance imaging|mri')
  GROUP BY h.hadm_id
)

SELECT
  los.los_group,
  aki.aki_type,
  COUNT(DISTINCT aki.subject_id) AS patient_count,
  AVG(COALESCE(img.mri_ct_count, 0)) AS mean_mri_ct_per_admission
FROM aki_patients aki
INNER JOIN los_calculation los
  ON aki.hadm_id = los.hadm_id
LEFT JOIN imaging_counts img
  ON aki.hadm_id = img.hadm_id
WHERE 
  los.los_group IS NOT NULL
GROUP BY los.los_group, aki.aki_type
ORDER BY los.los_group, aki.aki_type;