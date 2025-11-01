WITH stroke_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON d.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON d.hadm_id = a.hadm_id
  WHERE p.anchor_age BETWEEN 52 AND 62
    AND p.gender = 'M'
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '43%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I6%')
    )
),
comorbidities AS (
  SELECT
    sp.subject_id,
    sp.hadm_id,
    sp.hospital_expire_flag,
    CASE 
      WHEN d.icd_version = 9 AND d.icd_code LIKE '585%' THEN 1
      WHEN d.icd_version = 10 AND d.icd_code LIKE 'N18%' THEN 1
      ELSE 0
    END AS ckd_flag,
    CASE 
      WHEN d.icd_version = 9 AND d.icd_code LIKE '250%' THEN 1
      WHEN d.icd_version = 10 AND d.icd_code IN ('E10','E11','E12','E13','E14') THEN 1
      ELSE 0
    END AS diabetes_flag,
    CASE 
      WHEN i.stay_id IS NOT NULL THEN 1
      ELSE 0
    END AS icu_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM stroke_patients sp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON sp.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON sp.subject_id = d.subject_id AND sp.hadm_id = d.hadm_id
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '585%' OR d.icd_code LIKE '250%'))
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code IN ('E10','E11','E12','E13','E14')))
    )
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON sp.hadm_id = i.hadm_id
),
comorbidity_counts AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    MAX(ckd_flag) AS ckd_flag,
    MAX(diabetes_flag) AS diabetes_flag,
    MAX(icu_flag) AS icu_flag,
    MAX(los) AS los,
    COUNT(*) AS total_comorbidities
  FROM comorbidities
  WHERE ckd_flag = 1 OR diabetes_flag = 1
  GROUP BY subject_id, hadm_id, hospital_expire_flag
),
final_with_tertile AS (
  SELECT *,
    NTILE(3) OVER (ORDER BY total_comorbidities) AS comorbidity_tertile
  FROM comorbidity_counts
)
SELECT
  icu_flag,
  CASE WHEN los <= 5 THEN 'LOS <=5' ELSE 'LOS >5' END AS los_group,
  comorbidity_tertile,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(ckd_flag) * 100 AS ckd_prevalence_pct,
  AVG(diabetes_flag) * 100 AS diabetes_prevalence_pct
FROM final_with_tertile
GROUP BY icu_flag, los_group, comorbidity_tertile
ORDER BY icu_flag, los_group, comorbidity_tertile;