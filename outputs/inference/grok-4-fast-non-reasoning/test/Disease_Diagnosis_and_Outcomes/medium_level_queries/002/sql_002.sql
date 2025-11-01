WITH cohort AS (
  SELECT DISTINCT 
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 'ICD-9' AND di.icd_code LIKE '410%' AND di.icd_code NOT LIKE '410.%.2')
          OR (di.icd_version = 'ICD-10' AND di.icd_code LIKE 'I21%')
        )
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` ex
      WHERE ex.hadm_id = a.hadm_id
        AND (
          -- Shock
          (ex.icd_version = 'ICD-9' AND ex.icd_code = '785.50')
          OR (ex.icd_version = 'ICD-10' AND ex.icd_code LIKE 'R57%')
          OR
          -- Respiratory failure
          (ex.icd_version = 'ICD-9' AND ex.icd_code IN ('518.81', '518.82', '799.1'))
          OR (ex.icd_version = 'ICD-10' AND ex.icd_code LIKE 'J96%')
        )
    )
),
comorbidities AS (
  SELECT 
    c.*,
    CASE 
      WHEN c.los <= 5 THEN 'LOS ≤5 days'
      ELSE 'LOS >5 days'
    END AS los_group,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = c.hadm_id
        AND (
          (d.icd_version = 'ICD-9' AND d.icd_code IN ('585%', '586%'))
          OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'N18%')
        )
    ) AS has_ckd,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = c.hadm_id
        AND (
          (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '249%' OR d.icd_code LIKE '250%'))
          OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'E1[0-4]%')
        )
    ) AS has_diabetes
  FROM cohort c
)
SELECT 
  los_group,
  COUNT(hadm_id) AS num_admissions,
  SUM(hospital_expire_flag) AS num_deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id), 2) AS mortality_rate_pct,
  ROUND(AVG(CAST(has_ckd AS FLOAT)) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(CAST(has_diabetes AS FLOAT)) * 100, 2) AS diabetes_prevalence_pct
FROM comorbidities
GROUP BY los_group

UNION ALL

SELECT 
  'Overall' AS los_group,
  COUNT(hadm_id) AS num_admissions,
  SUM(hospital_expire_flag) AS num_deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id), 2) AS mortality_rate_pct,
  ROUND(AVG(CAST(has_ckd AS FLOAT)) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(CAST(has_diabetes AS FLOAT)) * 100, 2) AS diabetes_prevalence_pct
FROM comorbidities

ORDER BY 
  CASE los_group 
    WHEN 'LOS ≤5 days' THEN 1 
    WHEN 'LOS >5 days' THEN 2 
    ELSE 3 
  END
;
-- Note: To compute absolute/relative mortality differences, run post-query:
-- ABS(rate_long - rate_short) as absolute_diff_pct
-- (rate_long / rate_short) as relative_ratio
-- ((rate_long - rate_short) / rate_short * 100) as relative_diff_pct
-- Where rate_short is from LOS ≤5, rate_long from >5.;