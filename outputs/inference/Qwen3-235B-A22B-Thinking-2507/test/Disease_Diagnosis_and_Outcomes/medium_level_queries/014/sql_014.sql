WITH base_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL
),
hf_admissions AS (
  SELECT 
    base.*
  FROM base_admissions base
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE diag.hadm_id = base.hadm_id
      AND (
        (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
        OR
        (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
      )
  )
),
hf_with_icu AS (
  SELECT 
    hf.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = hf.hadm_id
          AND DATE(icu.intime) = DATE(hf.admittime)
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status
  FROM hf_admissions hf
),
hf_with_conditions AS (
  SELECT 
    hf.hadm_id,
    hf.hospital_expire_flag,
    hf.icu_status,
    DATE_DIFF(CAST(hf.dischtime AS DATE), CAST(hf.admittime AS DATE), DAY) AS los_days,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%') 
          THEN 1 
          ELSE 0 
        END) AS has_diabetes,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%') 
          THEN 1 
          ELSE 0 
        END) AS has_ckd
  FROM hf_with_icu hf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON hf.hadm_id = d.hadm_id
  GROUP BY hf.hadm_id, hf.hospital_expire_flag, hf.icu_status, los_days
),
hf_final AS (
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
      ELSE NULL 
    END AS los_group
  FROM hf_with_conditions
  WHERE los_days >= 1
)
SELECT
  icu_status,
  los_group,
  COUNT(*) AS n,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  AVG(has_diabetes) * 100 AS diabetes_prev,
  AVG(has_ckd) * 100 AS ckd_prev
FROM hf_final
WHERE los_group IS NOT NULL
GROUP BY icu_status, los_group
ORDER BY icu_status, 
  CASE los_group
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '>=8' THEN 3
  END;