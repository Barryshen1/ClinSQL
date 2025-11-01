WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_category,
    CASE 
      WHEN icu.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_strat
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 40 AND 50
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND diag.icd_version = 10
        AND diag.icd_code LIKE 'I63%'
    )
),

imaging_procedures AS (
  SELECT 
    proc.subject_id,
    proc.hadm_id,
    COUNT(DISTINCT proc.seq_num) AS num_imaging
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code
    AND proc.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%ct%'
    OR LOWER(dicd.long_title) LIKE '%mri%'
    OR LOWER(dicd.long_title) LIKE '%ultrasound%'
    OR LOWER(dicd.long_title) LIKE '%angiography%'
    OR LOWER(dicd.long_title) LIKE '%x-ray%'
    OR LOWER(dicd.long_title) LIKE '%scan%'
  GROUP BY proc.subject_id, proc.hadm_id
)

SELECT 
  c.los_category,
  c.icu_strat,
  COUNT(DISTINCT c.hadm_id) AS num_admissions,
  COALESCE(AVG(ip.num_imaging), 0) AS mean_imaging,
  COALESCE(MIN(ip.num_imaging), 0) AS min_imaging,
  COALESCE(MAX(ip.num_imaging), 0) AS max_imaging
FROM cohort c
LEFT JOIN imaging_procedures ip
  ON c.hadm_id = ip.hadm_id
GROUP BY c.los_category, c.icu_strat
ORDER BY c.los_category, c.icu_strat;