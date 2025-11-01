WITH patients_filtered AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
),

hf_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE d.seq_num = 1
    AND LOWER(did.long_title) LIKE '%heart failure%'
    AND d.subject_id IN (SELECT subject_id FROM patients_filtered)
),

icu_admissions AS (
  SELECT DISTINCT i.hadm_id,
    CASE 
      WHEN i.los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN i.los BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_stratum
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN hf_admissions hf ON i.hadm_id = hf.hadm_id
  WHERE i.los >= 1 AND i.los <= 7
),

ct_mri_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%ct%' OR LOWER(label) LIKE '%mri%'
),

ct_mri_counts AS (
  SELECT c.hadm_id, COUNT(*) AS ct_mri_count
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  INNER JOIN ct_mri_items cm ON c.itemid = cm.itemid
  WHERE c.hadm_id IS NOT NULL
  GROUP BY c.hadm_id
)

SELECT 
  ia.los_stratum,
  COUNT(ia.hadm_id) AS admission_count,
  AVG(COALESCE(cm.ct_mri_count, 0)) AS mean_ct_mri_per_admission
FROM icu_admissions ia
LEFT JOIN ct_mri_counts cm ON ia.hadm_id = cm.hadm_id
GROUP BY ia.los_stratum
ORDER BY ia.los_stratum;