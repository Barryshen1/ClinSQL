WITH sepsis_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%septic shock%'
  GROUP BY p.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
),
comorbidity_flags AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    -- CKD flag
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS ckd_flag,
    -- Diabetes
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS dm_flag,
    -- Atrial fibrillation
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%atrial fibrillation%' THEN 1 ELSE 0 END) AS af_flag,
    -- Hypertension
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%hypertension%' 
                  OR LOWER(dd.long_title) LIKE '%high blood pressure%' THEN 1 ELSE 0 END) AS htn_flag
  FROM sepsis_cohort sc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON sc.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  GROUP BY sc.subject_id, sc.hadm_id
),
final AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    CASE 
      WHEN DATETIME_DIFF(sc.dischtime, sc.admittime, DAY) <= 5 THEN '≤5 days'
      ELSE '>5 days'
    END AS los_group,
    cf.ckd_flag,
    cf.dm_flag,
    cf.af_flag,
    cf.htn_flag,
    sc.hospital_expire_flag
  FROM sepsis_cohort sc
  JOIN comorbidity_flags cf
    ON sc.subject_id = cf.subject_id AND sc.hadm_id = cf.hadm_id
)
SELECT
  los_group,
  ckd_flag,
  dm_flag,
  af_flag,
  htn_flag,
  COUNT(*) AS n_admissions,
  ROUND(100 * AVG(hospital_expire_flag),2) AS mortality_percent
FROM final
GROUP BY los_group, ckd_flag, dm_flag, af_flag, htn_flag
ORDER BY los_group, ckd_flag, dm_flag, af_flag, htn_flag;