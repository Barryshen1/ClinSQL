WITH tia_admissions AS (
  SELECT DISTINCT adm.subject_id,
         adm.hadm_id,
         p.gender,
         p.anchor_age,
         DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.subject_id = di.subject_id
   AND adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code
   AND di.icd_version = ddi.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(ddi.long_title) LIKE '%transient ischemic attack%'
    AND DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) BETWEEN 1 AND 7
),
ct_mri_counts AS (
  SELECT ta.subject_id,
         ta.hadm_id,
         ta.los_days,
         CASE 
           WHEN ta.los_days BETWEEN 1 AND 3 THEN '1-3 days'
           WHEN ta.los_days BETWEEN 4 AND 7 THEN '4-7 days'
         END AS los_bucket,
         COUNT(proc.icd_code) AS num_ct_mri
  FROM tia_admissions ta
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON ta.subject_id = proc.subject_id
   AND ta.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON proc.icd_code = dp.icd_code
   AND proc.icd_version = dp.icd_version
  WHERE dp.long_title LIKE '%CT%' 
     OR dp.long_title LIKE '%MRI%'
     OR dp.long_title LIKE '%magnetic resonance%' 
     OR dp.long_title LIKE '%computed tomography%'
  GROUP BY ta.subject_id, ta.hadm_id, ta.los_days, los_bucket
),
icu_flagged AS (
  SELECT c.subject_id,
         c.hadm_id,
         c.los_bucket,
         c.num_ct_mri,
         CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_use
  FROM ct_mri_counts c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.subject_id = icu.subject_id
   AND c.hadm_id = icu.hadm_id
)
SELECT 
  los_bucket,
  icu_use,
  APPROX_QUANTILES(num_ct_mri, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(num_ct_mri, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(num_ct_mri, 4)[OFFSET(3)] AS Q3
FROM icu_flagged
GROUP BY los_bucket, icu_use
ORDER BY los_bucket, icu_use;