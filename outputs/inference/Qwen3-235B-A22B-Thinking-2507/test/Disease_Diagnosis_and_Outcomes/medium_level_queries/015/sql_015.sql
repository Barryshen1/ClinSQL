WITH base AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    -- ICU status: Check existence in icustays
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.hadm_id = a.hadm_id
      ) THEN 'ICU' 
      ELSE 'non-ICU' 
    END AS icu_status,
    -- Hospital LOS in days (only completed admissions)
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Comorbidity count (non-stroke diagnoses)
    COALESCE((
      SELECT COUNT(DISTINCT d.icd_code)
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND NOT (  -- Exclude stroke codes
          (d.icd_version = 9 AND d.icd_code IN ('430','431','432','433','434','435','436'))
          OR 
          (d.icd_version = 10 AND (
            d.icd_code LIKE 'I60%' OR 
            d.icd_code LIKE 'I61%' OR 
            d.icd_code LIKE 'I62%' OR 
            d.icd_code LIKE 'I63%' OR 
            d.icd_code LIKE 'I64%' OR 
            d.icd_code LIKE 'G45%'
          ))
        )
    ), 0) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    -- Age 48-58 at admission
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
    -- Completed admissions only
    AND a.dischtime IS NOT NULL
    -- At least one stroke diagnosis
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('430','431','432','433','434','435','436'))
          OR 
          (d.icd_version = 10 AND (
            d.icd_code LIKE 'I60%' OR 
            d.icd_code LIKE 'I61%' OR 
            d.icd_code LIKE 'I62%' OR 
            d.icd_code LIKE 'I63%' OR 
            d.icd_code LIKE 'I64%' OR 
            d.icd_code LIKE 'G45%'
          ))
        )
    )
),
stratified AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    icu_status,
    -- Hospital LOS group
    CASE WHEN los_days <= 5 THEN '≤5' ELSE '>5' END AS los_group,
    -- Comorbidity burden group
    CASE WHEN comorbidity_count <= 2 THEN 'Low' ELSE 'High' END AS burden_group
  FROM base
)
SELECT
  icu_status,
  los_group,
  burden_group,
  COUNT(*) AS n,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
  -- Lower 95% CI bound (percentage)
  ROUND(
    GREATEST(0,  -- Prevent negative rates
      (SUM(hospital_expire_flag) / COUNT(*)) - 1.96 * SQRT(
        (SUM(hospital_expire_flag) / COUNT(*)) * 
        (1 - SUM(hospital_expire_flag) / COUNT(*)) / 
        COUNT(*)
      )
    ) * 100, 
    2
  ) AS lower_ci,
  -- Upper 95% CI bound (percentage)
  ROUND(
    LEAST(100,  -- Prevent >100% rates
      (SUM(hospital_expire_flag) / COUNT(*)) + 1.96 * SQRT(
        (SUM(hospital_expire_flag) / COUNT(*)) * 
        (1 - SUM(hospital_expire_flag) / COUNT(*)) / 
        COUNT(*)
      )
    ) * 100, 
    2
  ) AS upper_ci
FROM stratified
GROUP BY icu_status, los_group, burden_group
ORDER BY icu_status, los_group, burden_group;