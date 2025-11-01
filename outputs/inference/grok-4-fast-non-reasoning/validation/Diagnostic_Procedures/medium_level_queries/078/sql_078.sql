WITH tia_admissions AS (
  -- Flag admissions with TIA diagnosis
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%transient ischemic attack%'
),
imaging_counts AS (
  -- Count unique CT/MRI studies per admission
  SELECT 
    e.subject_id,
    e.hadm_id,
    COUNT(DISTINCT 
      CASE 
        WHEN LOWER(e.medication) LIKE '%ct%' OR LOWER(e.medication) LIKE '%computed tomography%' 
        THEN e.emar_id 
        WHEN LOWER(e.medication) LIKE '%mri%' OR LOWER(e.medication) LIKE '%magnetic resonance%' 
        THEN e.emar_id 
      END
    ) AS total_studies
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON e.pharmacy_id = p.pharmacy_id
  WHERE e.medication IS NOT NULL  -- Ensure medication field populated
  GROUP BY e.subject_id, e.hadm_id
),
base_cohort AS (
  -- Base cohort with filters
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    pa.gender,
    pa.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_group,
    CASE WHEN icu.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pa
    ON a.subject_id = pa.subject_id
  JOIN tia_admissions tia
    ON a.subject_id = tia.subject_id AND a.hadm_id = tia.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
  WHERE pa.gender = 'F'
    AND pa.anchor_age BETWEEN 88 AND 98
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths for cleaner cohort (optional, but common)
)
SELECT 
  bc.los_group,
  bc.icu_use,
  APPROX_QUANTILES(COALESCE(ic.total_studies, 0), 4)[OFFSET(2)] AS median_studies,
  (APPROX_QUANTILES(COALESCE(ic.total_studies, 0), 4)[OFFSET(3)] - 
   APPROX_QUANTILES(COALESCE(ic.total_studies, 0), 4)[OFFSET(1)]) AS iqr_studies
FROM base_cohort bc
LEFT JOIN imaging_counts ic
  ON bc.subject_id = ic.subject_id AND bc.hadm_id = ic.hadm_id
WHERE bc.los_group IS NOT NULL
GROUP BY bc.los_group, bc.icu_use
ORDER BY bc.los_group, bc.icu_use;