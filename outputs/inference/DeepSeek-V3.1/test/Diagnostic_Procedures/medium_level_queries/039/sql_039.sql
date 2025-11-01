WITH asthma_patients AS (
  SELECT 
    p.subject_id, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    DATE_DIFF(a.admittime, DATE(a.admittime), DAY) + 1 AS adm_day,
    CASE 
      WHEN DATE_DIFF(a.admittime, DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(a.admittime, DATE(a.admittime), DAY) + 1 BETWEEN 5 AND 8 THEN '5-8'
      ELSE 'Other'
    END AS day_group,
    CASE WHEN i.first_careunit IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.icd_code LIKE 'J45%'  -- Asthma codes
        AND di.icd_version = 10
    )
),
ct_mri_procedures AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT CONCAT(p.icd_code, p.icd_version)) AS num_ct_mri
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%CT%' OR d.long_title LIKE '%MRI%'
  GROUP BY hadm_id
)
SELECT 
  ap.day_group,
  ap.icu_status,
  COUNT(ap.hadm_id) AS num_admissions,
  AVG(COALESCE(cmp.num_ct_mri, 0)) AS mean_ct_mri,
  MIN(COALESCE(cmp.num_ct_mri, 0)) AS min_ct_mri,
  MAX(COALESCE(cmp.num_ct_mri, 0)) AS max_ct_mri
FROM asthma_patients ap
LEFT JOIN ct_mri_procedures cmp
  ON ap.hadm_id = cmp.hadm_id
WHERE ap.adm_day BETWEEN 1 AND 8
GROUP BY ap.day_group, ap.icu_status
ORDER BY ap.day_group, ap.icu_status;