WITH base AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
    AND p.gender = 'F'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) > 0
),
ami_cohort AS (
  SELECT 
    b.*,
    -- AMI filter already applied via WHERE
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dc
      WHERE dc.hadm_id = b.hadm_id
        AND (
          (dc.icd_version = 9 AND dc.icd_code LIKE '585.%') 
          OR (dc.icd_version = 9 AND dc.icd_code = '586')
          OR (dc.icd_version = 10 AND dc.icd_code LIKE 'N18.%')
        )
    ) AS has_ckd,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dd
      WHERE dd.hadm_id = b.hadm_id
        AND (
          (dd.icd_version = 9 AND dd.icd_code LIKE '250.%')
          OR (dd.icd_version = 10 AND (
            dd.icd_code LIKE 'E10.%' OR 
            dd.icd_code LIKE 'E11.%' OR 
            dd.icd_code LIKE 'E13.%'
          ))
        )
    ) AS has_diabetes
  FROM base b
  WHERE 62 <= b.age_at_adm 
    AND b.age_at_adm <= 72
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = b.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410.%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
        )
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` ds
      WHERE ds.hadm_id = b.hadm_id
        AND (
          (ds.icd_version = 9 AND ds.icd_code LIKE '785.5%')
          OR (ds.icd_version = 10 AND (
            ds.icd_code = 'R57.0' OR 
            ds.icd_code = 'I46.0'
          ))
        )
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dr
      WHERE dr.hadm_id = b.hadm_id
        AND (
          (dr.icd_version = 9 AND dr.icd_code IN ('518.81', '518.82', '518.84', '799.1'))
          OR (dr.icd_version = 10 AND dr.icd_code LIKE 'J96.%')
        )
    )
),
summary AS (
  SELECT 
    CASE 
      WHEN los_days <= 5 THEN '<= 5 days'
      ELSE '> 5 days'
    END AS los_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS num_deaths,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN has_ckd THEN 1 ELSE 0 END) / COUNT(*), 2) AS ckd_prevalence_pct,
    ROUND(100.0 * SUM(CASE WHEN has_diabetes THEN 1 ELSE 0 END) / COUNT(*), 2) AS diabetes_prevalence_pct
  FROM ami_cohort
  GROUP BY 1
)
SELECT 
  los_group,
  total_patients,
  num_deaths,
  mortality_rate_pct,
  ckd_prevalence_pct,
  diabetes_prevalence_pct
FROM summary

UNION ALL

SELECT 
  'Absolute mortality difference (>5 - <=5 days) %' AS los_group,
  NULL AS total_patients,
  NULL AS num_deaths,
  s_long.mortality_rate_pct - s_short.mortality_rate_pct AS mortality_rate_pct,
  NULL AS ckd_prevalence_pct,
  NULL AS diabetes_prevalence_pct
FROM summary s_short
CROSS JOIN summary s_long
WHERE s_short.los_group = '<= 5 days'
  AND s_long.los_group = '> 5 days'

UNION ALL

SELECT 
  'Relative mortality difference (>5 / <=5 - 1) %' AS los_group,
  NULL AS total_patients,
  NULL AS num_deaths,
  ROUND(((s_long.mortality_rate_pct - s_short.mortality_rate_pct) / s_short.mortality_rate_pct) * 100, 2) AS mortality_rate_pct,
  NULL AS ckd_prevalence_pct,
  NULL AS diabetes_prevalence_pct
FROM summary s_short
CROSS JOIN summary s_long
WHERE s_short.los_group = '<= 5 days'
  AND s_long.los_group = '> 5 days'

ORDER BY 
  CASE los_group 
    WHEN '<= 5 days' THEN 1
    WHEN '> 5 days' THEN 2
    ELSE 3 
  END;