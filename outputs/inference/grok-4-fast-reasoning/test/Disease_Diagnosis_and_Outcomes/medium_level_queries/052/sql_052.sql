WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender, 
    p.anchor_age,
    CASE 
      WHEN EXISTS(
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
      ) THEN 'ICU' 
      ELSE 'non-ICU' 
    END AS icu_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
    AND EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 
           AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' 
                OR d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '436%' 
                OR d.icd_code LIKE '437%' OR d.icd_code LIKE '438%')) 
          OR 
          (d.icd_version = 10 
           AND REGEXP_CONTAINS(d.icd_code, r'^I6[0-9]'))
        )
    )
),
comorb AS (
  SELECT 
    c.*,
    (SELECT COUNT(DISTINCT d.icd_code) 
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
     WHERE d.hadm_id = c.hadm_id
    ) AS num_comorb
  FROM cohort c
),
tertile_cte AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY num_comorb ASC) AS comorbidity_tertile
  FROM comorb
),
with_flags AS (
  SELECT 
    t.*,
    CASE WHEN t.los_days <= 5 THEN '<=5' ELSE '>5' END AS los_group,
    EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = t.hadm_id
        AND (
          (d.icd_version = 9 AND (d.icd_code LIKE '585%' OR d.icd_code = '586')) 
          OR 
          (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
        )
    ) AS has_ckd,
    EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = t.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%') 
          OR 
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^(E10|E11|E12|E13|E14)'))
        )
    ) AS has_diabetes
  FROM tertile_cte t
)
SELECT 
  icu_stay,
  los_group,
  comorbidity_tertile,
  COUNT(*) AS total_admissions,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(CAST(has_ckd AS INT64)) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(CAST(has_diabetes AS INT64)) * 100, 2) AS diabetes_prevalence_pct
FROM with_flags
GROUP BY icu_stay, los_group, comorbidity_tertile
ORDER BY icu_stay, los_group, comorbidity_tertile;