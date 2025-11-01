WITH cohort AS (
  -- Base cohort: males 77-87, asthma exacerbation (primary dx), LOS 1-8 days, discharged alive
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    p.anchor_age,
    CASE 
      WHEN has_icu_transfer = 1 THEN 1 
      ELSE 0 
    END AS is_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id 
    AND d.seq_num = 1 
    AND d.icd_version = '10' 
    AND d.icd_code LIKE 'J45%'
  LEFT JOIN (
    SELECT 
      hadm_id,
      MAX(CASE WHEN careunit LIKE '%ICU%' THEN 1 ELSE 0 END) AS has_icu_transfer
    FROM `physionet-data.mimiciv_3_1_hosp.transfers`
    GROUP BY hadm_id
  ) t
    ON a.hadm_id = t.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
    AND a.hospital_expire_flag = 0
    AND p.dod IS NULL
),

imaging_counts AS (
  -- Count distinct CT/MRI HCPCS codes per hadm_id (proxy for imaging events)
  SELECT 
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE dh.category = 'RADIOLOGY'
    AND (h.hcpcs_cd LIKE '70%' OR h.hcpcs_cd LIKE '71%')  -- CT/MRI in 70xxx-71xxx ranges
    AND (h.hcpcs_cd LIKE '%CT%' OR h.hcpcs_cd LIKE '%MRI%' OR h.hcpcs_cd IN ('70450', '70551', '71250', '72141'))  -- Example specific codes; extend as needed
  GROUP BY h.hadm_id
)

SELECT 
  CASE 
    WHEN c.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    ELSE '5-8 days'
  END AS los_bin,
  CASE WHEN c.is_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS location,
  COUNT(*) AS total_admissions,
  AVG(COALESCE(i.ct_mri_count, 0)) AS mean_ct_mri,
  MIN(COALESCE(i.ct_mri_count, 0)) AS min_ct_mri,
  MAX(COALESCE(i.ct_mri_count, 0)) AS max_ct_mri
FROM cohort c
LEFT JOIN imaging_counts i
  ON c.hadm_id = i.hadm_id
GROUP BY los_bin, location
ORDER BY los_bin, location;