WITH 
  -- Identify TIA patients
  tia_patients AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE dd.long_title LIKE '%Transient ischemic attack%'
    AND a.subject_id IN (
      SELECT subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.patients`
      WHERE anchor_age BETWEEN 88 AND 98
      AND gender = 'F'
    )
  ),
  
  -- Identify CT/MRI procedures
  ct_mri_procedures AS (
    SELECT hadm_id, COUNT(*) as ct_mri_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE icd_code IN (
      SELECT icd_code
      FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
      WHERE long_title LIKE '%CT%' OR long_title LIKE '%MRI%'
    )
    GROUP BY hadm_id
  ),
  
  -- ICU stay information
  icu_stays AS (
    SELECT hadm_id, COUNT(*) > 0 as icu_use
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY hadm_id
  ),
  
  -- Hospital stay lengths
  stay_lengths AS (
    SELECT hadm_id,
           CASE
             WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
             WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
             ELSE 'Other'
           END as stay_length
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  )

-- Combine and analyze
SELECT 
  COALESCE(s.stay_length, 'Unknown') as stay_length,
  icu_use,
  APPROX_QUANTILES(ct_mri_count, 0.5)[OFFSET(1)] as median_ct_mri,
  APPROX_QUANTILES(ct_mri_count, 0.25)[OFFSET(1)] as q1_ct_mri,
  APPROX_QUANTILES(ct_mri_count, 0.75)[OFFSET(1)] as q3_ct_mri
FROM tia_patients tp
JOIN ct_mri_procedures cm ON tp.hadm_id = cm.hadm_id
LEFT JOIN icu_stays i ON tp.hadm_id = i.hadm_id
LEFT JOIN stay_lengths s ON tp.hadm_id = s.hadm_id
GROUP BY stay_length, icu_use
ORDER BY stay_length, icu_use;