WITH base_admissions AS (
  -- Filter admissions for 77-87 year-old male with asthma exacerbation and LOS 1-8 days
  SELECT DISTINCT a.subject_id, a.hadm_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE p.anchor_age BETWEEN 77 AND 87
    AND p.gender = 'M'
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'J45%')
      OR (di.icd_version = 9 AND di.icd_code LIKE '493%')
    )
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
admissions_with_icu AS (
  -- Determine ICU vs Non-ICU status for each admission
  SELECT s.subject_id, s.hadm_id, s.los_days,
         CASE WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
             WHERE icu.subject_id = s.subject_id AND icu.hadm_id = s.hadm_id
         ) THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM base_admissions s
),
ct_mri_per_admission AS (
  -- Count CT/MRI imaging events per admission using ICU chart events
  SELECT hadm_id, COUNT(*) AS count_ct_mri
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ct%' OR LOWER(di.label) LIKE '%mri%'
  GROUP BY hadm_id
)
SELECT
  CASE
     WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4'
     WHEN a.los_days BETWEEN 5 AND 8 THEN '5-8'
  END AS los_group,
  a.icu_status,
  AVG(COALESCE(ct.count_ct_mri, 0)) AS mean_ct_mri_per_admission,
  MIN(COALESCE(ct.count_ct_mri, 0)) AS min_ct_mri_per_admission,
  MAX(COALESCE(ct.count_ct_mri, 0)) AS max_ct_mri_per_admission
FROM admissions_with_icu a
LEFT JOIN ct_mri_per_admission ct
  ON a.hadm_id = ct.hadm_id
GROUP BY los_group, a.icu_status
ORDER BY los_group, a.icu_status;