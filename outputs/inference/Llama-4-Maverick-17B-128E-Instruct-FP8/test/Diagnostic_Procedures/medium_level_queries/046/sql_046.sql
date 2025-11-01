WITH tia_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 50 AND 60
  AND dicd.long_title LIKE '%Transient ischemic attack%'
),
los_ct_mri AS (
  SELECT tp.subject_id, tp.hadm_id,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         COUNT(pe.itemid) AS ct_mri_count
  FROM tia_patients tp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON tp.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON tp.hadm_id = pe.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label IN ('CT', 'MRI') OR di.label LIKE '%CT%' OR di.label LIKE '%MRI%'
  GROUP BY tp.subject_id, tp.hadm_id, a.admittime, a.dischtime
)
SELECT 
  CASE 
    WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other'
  END AS los_category,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(ct_mri_count) AS mean_ct_mri_procedures
FROM los_ct_mri
WHERE los BETWEEN 1 AND 7
GROUP BY los_category
ORDER BY los_category;