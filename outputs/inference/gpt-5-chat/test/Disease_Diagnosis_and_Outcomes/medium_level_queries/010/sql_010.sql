WITH base AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
),
ami_cases AS (
  SELECT DISTINCT b.hadm_id
  FROM base b
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON b.hadm_id = dx.hadm_id
  WHERE (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%'))
     OR (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
),
exclude_cases AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND (icd_code LIKE 'R57%' OR icd_code LIKE 'J96%'))
     OR (icd_version = 9 AND (icd_code LIKE '7855%' OR icd_code LIKE '51881' OR icd_code LIKE '51882'))
),
comorbidity_flags AS (
  SELECT
    b.hadm_id,
    COUNT(DISTINCT dx.icd_code) AS comorb_count,
    MAX(CASE
          WHEN (dx.icd_version = 10 AND dx.icd_code LIKE 'N18%')
            OR (dx.icd_version = 9 AND dx.icd_code LIKE '585%')
          THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE
          WHEN (dx.icd_version = 10 AND dx.icd_code BETWEEN 'E10' AND 'E14')
            OR (dx.icd_version = 9 AND dx.icd_code LIKE '250%')
          THEN 1 ELSE 0 END) AS has_diabetes
  FROM base b
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON b.hadm_id = dx.hadm_id
  WHERE b.hadm_id IN (SELECT hadm_id FROM ami_cases)
    AND b.hadm_id NOT IN (SELECT hadm_id FROM exclude_cases)
    -- exclude AMI/shock/resp failure codes from comorbidity counting
    AND NOT (
      (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%' OR dx.icd_code LIKE 'R57%' OR dx.icd_code LIKE 'J96%'))
      OR (dx.icd_version = 9 AND (dx.icd_code LIKE '410%' OR dx.icd_code LIKE '7855%' OR dx.icd_code LIKE '51881' OR dx.icd_code LIKE '51882'))
    )
  GROUP BY b.hadm_id
),
los_quartiles AS (
  SELECT
    b.*,
    cf.comorb_count,
    cf.has_ckd,
    cf.has_diabetes,
    CASE
      WHEN cf.comorb_count <= 1 THEN 'low'
      WHEN cf.comorb_count BETWEEN 2 AND 3 THEN 'med'
      ELSE 'high'
    END AS comorb_cat,
    NTILE(4) OVER (ORDER BY b.los_days) AS los_quartile
  FROM base b
  JOIN comorbidity_flags cf
    ON b.hadm_id = cf.hadm_id
  WHERE b.hadm_id IN (SELECT hadm_id FROM ami_cases)
    AND b.hadm_id NOT IN (SELECT hadm_id FROM exclude_cases)
),
stats AS (
  SELECT
    los_quartile,
    comorb_cat,
    COUNT(*) AS n,
    AVG(hospital_expire_flag) AS mort_rate,
    AVG(has_ckd) AS ckd_prev,
    AVG(has_diabetes) AS diab_prev
  FROM los_quartiles
  GROUP BY los_quartile, comorb_cat
)
SELECT
  los_quartile,
  comorb_cat,
  n,
  mort_rate,
  mort_rate - 1.96 * SQRT(mort_rate*(1-mort_rate)/n) AS mort_rate_ci_lower,
  mort_rate + 1.96 * SQRT(mort_rate*(1-mort_rate)/n) AS mort_rate_ci_upper,
  ckd_prev,
  diab_prev
FROM stats
ORDER BY los_quartile, comorb_cat;