WITH target_population AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM physionet-data.mimiciv_3_1_icu.icustays i 
        WHERE i.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_group,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM physionet-data.mimiciv_3_1_icu.icustays i 
        WHERE i.hadm_id = a.hadm_id
      ) THEN (
        SELECT MIN(i.los) 
        FROM physionet-data.mimiciv_3_1_icu.icustays i 
        WHERE i.hadm_id = a.hadm_id
      )
      ELSE DATETIME_DIFF(a.dischtime, a.admittime, DAY)
    END AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
),
hf_diagnoses AS (
  SELECT DISTINCT
    d.icd_code,
    d.icd_version
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
),
admission_diagnoses AS (
  SELECT
    di.hadm_id,
    COUNT(*) AS total_diagnoses,
    COUNT(hf.icd_code) AS hf_diagnoses
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  LEFT JOIN hf_diagnoses hf ON di.icd_code = hf.icd_code AND di.icd_version = hf.icd_version
  GROUP BY di.hadm_id
)
SELECT
  tp.icu_group,
  SUM(CASE WHEN tp.los_days <= 3 THEN 1 ELSE 0 END) AS los_leq3,
  SUM(CASE WHEN tp.los_days BETWEEN 4 AND 6 THEN 1 ELSE 0 END) AS los_4to6,
  SUM(CASE WHEN tp.los_days BETWEEN 7 AND 10 THEN 1 ELSE 0 END) AS los_7to10,
  SUM(CASE WHEN tp.los_days > 10 THEN 1 ELSE 0 END) AS los_gt10,
  SUM(tp.hospital_expire_flag) AS in_hospital_mortality,
  PERCENTILE_CONT(tp.los_days, 0.5) AS median_los,
  AVG(ad.total_diagnoses - ad.hf_diagnoses) AS avg_comorbidity_count
FROM target_population tp
JOIN admission_diagnoses ad ON tp.hadm_id = ad.hadm_id
GROUP BY tp.icu_group
ORDER BY tp.icu_group;