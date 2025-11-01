WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 4 THEN '1-4'
      ELSE '5-7'
    END AS los_bin
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pat.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 44 AND 54
    AND (
      (diag.icd_version = 10 AND diag.icd_code = 'G45.9') 
      OR (diag.icd_version = 9 AND diag.icd_code = '435.9')
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS num_imaging
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ct%' 
     OR LOWER(d.long_title) LIKE '%computed tomography%'
     OR LOWER(d.long_title) LIKE '%mri%' 
     OR LOWER(d.long_title) LIKE '%magnetic resonance%'
     OR LOWER(d.long_title) LIKE '%x-ray%' 
     OR LOWER(d.long_title) LIKE '%radiograph%'
     OR LOWER(d.long_title) LIKE '%ultrasound%' 
     OR LOWER(d.long_title) LIKE '%echo%'
  GROUP BY p.hadm_id
),
icu_use AS (
  SELECT 
    hadm_id,
    1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
final AS (
  SELECT 
    c.los_bin,
    COALESCE(u.icu_flag, 0) AS icu_use,
    COALESCE(i.num_imaging, 0) AS num_imaging
  FROM cohort c
  LEFT JOIN imaging i
    ON c.hadm_id = i.hadm_id
  LEFT JOIN icu_use u
    ON c.hadm_id = u.hadm_id
)
SELECT 
  los_bin,
  icu_use,
  APPROX_QUANTILES(num_imaging, 4)[SAFE_OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_imaging, 4)[SAFE_OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_imaging, 4)[SAFE_OFFSET(3)] AS p75
FROM final
GROUP BY los_bin, icu_use
ORDER BY los_bin, icu_use;