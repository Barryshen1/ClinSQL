WITH tia_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND LOWER(di.long_title) LIKE '%transient ischemic attack%'
),
ct_mri_procedures AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM physionet-data.mimiciv_3_1_icu.procedureevents p
  JOIN physionet-data.mimiciv_3_1_icu.d_items d ON p.itemid = d.itemid
  WHERE (LOWER(d.label) LIKE '%ct%' OR LOWER(d.label) LIKE '%mri%')
    AND d.linksto = 'procedureevents'
  GROUP BY p.hadm_id
)
SELECT
  CASE
    WHEN ta.los_days BETWEEN 1 AND 3 THEN 'LOS 1-3 days'
    WHEN ta.los_days BETWEEN 4 AND 7 THEN 'LOS 4-7 days'
    ELSE 'Other'
  END AS los_group,
  COUNT(ta.hadm_id) AS patient_count,
  AVG(COALESCE(cmp.ct_mri_count, 0)) AS mean_ct_mri_procedures_per_admission
FROM tia_admissions ta
LEFT JOIN ct_mri_procedures cmp ON ta.hadm_id = cmp.hadm_id
WHERE ta.los_days BETWEEN 1 AND 7
GROUP BY los_group
ORDER BY los_group;