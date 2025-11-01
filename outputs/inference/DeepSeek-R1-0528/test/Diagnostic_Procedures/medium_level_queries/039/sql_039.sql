WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hosp,
    -- ICU flag: 1 if admission has ICU stay, else 0
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu ON adm.hadm_id = icu.hadm_id
  WHERE 
    pat.gender = 'M'
    -- Age at admission: anchor_age + (admission year - anchor_year)
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 77 AND 87
    -- Asthma exacerbation diagnosis
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
        ON diag.icd_code = d.icd_code 
        AND diag.icd_version = d.icd_version
      WHERE 
        diag.hadm_id = adm.hadm_id
        AND REGEXP_CONTAINS(d.long_title, r'(?i)asthma.*exacerbation')
    )
    -- LOS between 1-8 days (groups 1-4 and 5-8)
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 8
),

procedures AS (
  -- Procedures from ICD table
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON proc.icd_code = d.icd_code 
    AND proc.icd_version = d.icd_version
  WHERE 
    REGEXP_CONTAINS(d.long_title, r'(?i)computed tomography|CT |magnetic resonance|MRI')
  
  UNION ALL
  
  -- Procedures from HCPCS table
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpcs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON hcpcs.hcpcs_cd = d.code
  WHERE 
    REGEXP_CONTAINS(d.long_description, r'(?i)computed tomography|CT |magnetic resonance|MRI') 
    OR REGEXP_CONTAINS(d.short_description, r'(?i)computed tomography|CT |magnetic resonance|MRI')
),

procedure_counts AS (
  SELECT 
    c.hadm_id,
    c.los_hosp,
    c.icu_flag,
    -- Group admission duration
    CASE 
      WHEN c.los_hosp BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN c.los_hosp BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    -- Count procedures (0 if none)
    COUNT(DISTINCT p.hadm_id) AS ct_mri_count
  FROM cohort c
  LEFT JOIN procedures p 
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id, c.los_hosp, c.icu_flag
)

SELECT 
  los_group,
  CASE 
    WHEN icu_flag = 1 THEN 'ICU' 
    ELSE 'non-ICU' 
  END AS icu_stratum,
  AVG(ct_mri_count) AS mean_ct_mri,
  MIN(ct_mri_count) AS min_ct_mri,
  MAX(ct_mri_count) AS max_ct_mri,
  COUNT(*) AS num_admissions
FROM procedure_counts
GROUP BY los_group, icu_stratum
ORDER BY los_group, icu_stratum;