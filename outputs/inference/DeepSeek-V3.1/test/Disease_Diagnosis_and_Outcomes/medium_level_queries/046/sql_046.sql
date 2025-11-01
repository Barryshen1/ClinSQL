WITH hf_admissions AS (
  SELECT 
      adm.subject_id, 
      adm.hadm_id, 
      adm.admittime, 
      adm.dischtime, 
      adm.hospital_expire_flag,
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
      pt.gender,
      pt.anchor_age,
      CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
      (SELECT COUNT(DISTINCT diag.icd_code)
       FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
       WHERE diag.subject_id = adm.subject_id 
         AND diag.hadm_id = adm.hadm_id
         AND NOT (diag.icd_code LIKE 'I50%' OR diag.icd_code LIKE '428%')
      ) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
      ON adm.subject_id = pt.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON adm.hadm_id = icu.hadm_id
  WHERE pt.gender = 'M'
      AND pt.anchor_age BETWEEN 72 AND 82
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
          WHERE diag.subject_id = adm.subject_id 
            AND diag.hadm_id = adm.hadm_id
            AND (diag.icd_code LIKE 'I50%' OR diag.icd_code LIKE '428%')
      )
),

cohort_with_los_cat AS (
  SELECT *,
      CASE 
          WHEN los_days <= 3 THEN '<=3'
          WHEN los_days BETWEEN 4 AND 6 THEN '4-6'
          WHEN los_days BETWEEN 7 AND 10 THEN '7-10'
          ELSE '>10'
      END AS los_category
  FROM hf_admissions
)

SELECT 
    icu_status,
    los_category,
    COUNT(*) AS n_admissions,
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_rate_percent,
    ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
    ROUND(AVG(comorbidity_count), 2) AS avg_comorbidity_count
FROM cohort_with_los_cat
GROUP BY icu_status, los_category
ORDER BY icu_status, los_category;