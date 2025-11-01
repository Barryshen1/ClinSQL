WITH base_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(COALESCE(a.deathtime, a.dischtime), a.admittime, DAY) AS survival_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND (
            d.icd_code LIKE '480%' OR d.icd_code LIKE '481%' OR d.icd_code LIKE '482%' OR
            d.icd_code LIKE '483%' OR d.icd_code LIKE '484%' OR d.icd_code LIKE '485%' OR
            d.icd_code LIKE '486%'
          ))
          OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J(09|1[0-8])'))
        )
    )
),
comorb_scores AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorb_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
full_base AS (
  SELECT 
    b.*,
    COALESCE(c.comorb_score, 0) AS comorb_score
  FROM base_cohort AS b
  LEFT JOIN comorb_scores AS c
    ON b.hadm_id = c.hadm_id
),
q75_comorb AS (
  SELECT PERCENTILE_CONT(comorb_score, 0.75) AS q75_value
  FROM full_base
),
has_major_comp AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN condition_flag = 1 THEN 1 ELSE 0 END) AS has_major_comp
  FROM (
    SELECT 
      hadm_id,
      icd_version,
      icd_code,
      CASE 
        WHEN icd_version = 9 AND (
          icd_code LIKE '584%'  -- AKI
          OR icd_code LIKE '99591%' OR icd_code LIKE '038%' OR icd_code LIKE '7855%'  -- Sepsis
          OR icd_code IN ('51881', '51882', '51884')  -- Resp failure
        ) THEN 1
        WHEN icd_version = 10 AND (
          icd_code LIKE 'N17%'  -- AKI
          OR icd_code LIKE 'A41%' OR icd_code LIKE 'R652%'  -- Sepsis
          OR icd_code LIKE 'J96%'  -- Resp failure
        ) THEN 1
        ELSE 0
      END AS condition_flag
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  )
  GROUP BY hadm_id
),
target_cohort AS (
  SELECT 
    f.*,
    COALESCE(m.has_major_comp, 0) AS has_major_comp
  FROM full_base AS f
  CROSS JOIN q75_comorb AS q
  LEFT JOIN has_major_comp AS m
    ON f.hadm_id = m.hadm_id
  WHERE f.comorb_score >= q.q75_value
),
patient_comorb AS (
  SELECT PERCENTILE_CONT(comorb_score, 0.5) AS his_comorb
  FROM target_cohort
),
cohort_stats AS (
  SELECT 
    100.0 * COUNTIF(hospital_expire_flag = 1) / COUNT(*) AS mortality_pct,
    100.0 * COUNTIF(has_major_comp = 1) / COUNT(*) AS major_comp_pct,
    PERCENTILE_CONT(survival_days, 0.5) AS median_survival_days
  FROM target_cohort
),
final_calc AS (
  SELECT 
    tc.*,
    pc.his_comorb,
    cs.*
  FROM target_cohort AS tc
  CROSS JOIN patient_comorb AS pc
  CROSS JOIN cohort_stats AS cs
)
SELECT 
  100.0 * COUNTIF(anchor_age + comorb_score <= 78 + his_comorb) / COUNT(*) AS composite_risk_percentile,
  ANY_VALUE(mortality_pct) AS mortality_pct,
  ANY_VALUE(major_comp_pct) AS major_comp_pct,
  ANY_VALUE(median_survival_days) AS median_survival_days
FROM final_calc;