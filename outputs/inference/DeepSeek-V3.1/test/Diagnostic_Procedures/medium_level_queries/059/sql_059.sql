WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
        WHEN dx.seq_num = 1 THEN 'Primary HF'
        ELSE 'Secondary HF'
    END AS hf_type,
    -- Calculate age at admission
    (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE 
    pat.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 67 AND 77
    AND (
      (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%') OR
      (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
    )
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),

imaging_counts AS (
  SELECT 
    c.hadm_id,
    c.los_days,
    c.hf_type,
    COUNT(DISTINCT h.hcpcs_cd) AS num_imaging_studies
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON c.hadm_id = h.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE d.short_description LIKE '%RADIOLOGY%'
  GROUP BY c.hadm_id, c.los_days, c.hf_type
)

SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_group,
  hf_type,
  APPROX_QUANTILES(num_imaging_studies, 3) AS percentiles -- returns [p25, p50, p75]
FROM imaging_counts
GROUP BY los_group, hf_type
ORDER BY los_group, hf_type;