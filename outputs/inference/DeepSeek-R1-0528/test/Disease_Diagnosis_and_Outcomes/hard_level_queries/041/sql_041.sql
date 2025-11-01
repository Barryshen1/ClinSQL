WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    p.dod,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS admission_age,
    -- 30-day mortality flag
    CASE WHEN DATE_DIFF(DATE(p.dod), DATE(adm.admittime), DAY) <= 30 THEN 1 ELSE 0 END AS died_30d,
    -- AKI diagnosis flag
    MAX(
      CASE WHEN (
        (diag_aki.icd_version = 9 AND diag_aki.icd_code LIKE '584%') OR
        (diag_aki.icd_version = 10 AND diag_aki.icd_code LIKE 'N17%')
      ) THEN 1 ELSE 0 END
    ) AS aki_flag,
    -- ARDS diagnosis flag
    MAX(
      CASE WHEN (
        (diag_ards.icd_version = 9 AND diag_ards.icd_code = '518.82') OR
        (diag_ards.icd_version = 10 AND diag_ards.icd_code = 'J80')
      ) THEN 1 ELSE 0 END
    ) AS ards_flag,
    -- Survival days (for decedents)
    DATE_DIFF(DATE(p.dod), DATE(adm.admittime), DAY) AS survival_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  -- Ensure ICU stay
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  -- ICH diagnosis (any position)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_ich
    ON adm.hadm_id = diag_ich.hadm_id
    AND adm.subject_id = diag_ich.subject_id
    AND (
      (diag_ich.icd_version = 9 AND diag_ich.icd_code LIKE '430%') OR
      (diag_ich.icd_version = 9 AND diag_ich.icd_code LIKE '431%') OR
      (diag_ich.icd_version = 9 AND diag_ich.icd_code LIKE '432%') OR
      (diag_ich.icd_version = 10 AND diag_ich.icd_code LIKE 'I60%') OR
      (diag_ich.icd_version = 10 AND diag_ich.icd_code LIKE 'I61%') OR
      (diag_ich.icd_version = 10 AND diag_ich.icd_code LIKE 'I62%')
    )
  -- Left join for AKI diagnosis (to capture all admissions)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_aki
    ON adm.hadm_id = diag_aki.hadm_id
    AND adm.subject_id = diag_aki.subject_id
    AND (
      (diag_aki.icd_version = 9 AND diag_aki.icd_code LIKE '584%') OR
      (diag_aki.icd_version = 10 AND diag_aki.icd_code LIKE 'N17%')
    )
  -- Left join for ARDS diagnosis
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_ards
    ON adm.hadm_id = diag_ards.hadm_id
    AND adm.subject_id = diag_ards.subject_id
    AND (
      (diag_ards.icd_version = 9 AND diag_ards.icd_code = '518.82') OR
      (diag_ards.icd_version = 10 AND diag_ards.icd_code = 'J80')
    )
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 68 AND 78
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, p.dod, p.anchor_age, p.anchor_year
)

SELECT
  COUNT(*) AS cohort_size,
  ROUND(100 * AVG(died_30d), 2) AS mortality_30d_percent,
  ROUND(100 * AVG(aki_flag), 2) AS aki_rate_percent,
  ROUND(100 * AVG(ards_flag), 2) AS ards_rate_percent,
  NULL AS composite_risk_score_25th,
  NULL AS composite_risk_score_50th,
  NULL AS composite_risk_score_75th,
  -- Median survival among decedents (using approximate quantile)
  (SELECT APPROX_QUANTILES(survival_days, 100)[SAFE_OFFSET(50)] 
   FROM cohort 
   WHERE survival_days IS NOT NULL) AS median_survival_days_decedents
FROM cohort;