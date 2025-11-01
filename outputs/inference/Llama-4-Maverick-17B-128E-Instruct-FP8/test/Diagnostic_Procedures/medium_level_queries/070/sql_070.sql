WITH heart_failure_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, a.hadm_id, 
         CASE WHEN icu.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS had_icu_stay,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
         CASE 
           WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
           WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
           ELSE NULL
         END AS los_category
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 59 AND 69
  AND d_diag.long_title LIKE '%HEART FAILURE%'
),
radiography_counts AS (
  SELECT hadm_id, COUNT(*) AS ct_radiography_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_l ON l.itemid = d_l.itemid
  WHERE d_l.label LIKE '%Radiography%' OR d_l.label LIKE '%CT%'
  GROUP BY hadm_id
)
SELECT 
  hfp.had_icu_stay,
  hfp.los_category,
  APPROX_QUANTILES(rc.ct_radiography_count, 4)[OFFSET(1)] AS percentile_25,
  APPROX_QUANTILES(rc.ct_radiography_count, 4)[OFFSET(2)] AS percentile_50,
  APPROX_QUANTILES(rc.ct_radiography_count, 4)[OFFSET(3)] AS percentile_75
FROM heart_failure_patients hfp
JOIN radiography_counts rc ON hfp.hadm_id = rc.hadm_id
WHERE hfp.los_category IN ('1-4 days', '5-8 days')
GROUP BY hfp.had_icu_stay, hfp.los_category
ORDER BY hfp.had_icu_stay, hfp.los_category;