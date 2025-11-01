WITH qualifying_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
    ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 68 AND p.anchor_age <= 78
    AND (
      (diag.icd_version = '10' AND diag.icd_code LIKE 'I61%')
      OR (diag.icd_version = '9' AND (
        diag.icd_code LIKE '430%' OR diag.icd_code LIKE '431%' OR diag.icd_code LIKE '432%'
      ))
    )
),
filtered_cohort AS (
  SELECT 
    qa.subject_id,
    qa.hadm_id,
    qa.admittime,
    qa.dod
  FROM qualifying_admissions qa
  WHERE qa.rn = 1
    AND DATETIME_DIFF(qa.dischtime, (
      SELECT MAX(icu.outtime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = qa.hadm_id
    ), HOUR) > 0
),
cohort AS (
  SELECT 
    fc.*,
    CAST(drg.drg_mortality AS INT64) AS risk_score
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    ON fc.hadm_id = drg.hadm_id
    AND drg.drg_type = 'MS-DRG'
),
aki_flags AS (
  SELECT 
    c.*,
    CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki
  FROM cohort c
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (
      (icd_version = '10' AND icd_code LIKE 'N17%')
      OR (icd_version = '9' AND icd_code LIKE '584%')
    )
  ) aki ON c.subject_id = aki.subject_id AND c.hadm_id = aki.hadm_id
),
ards_flags AS (
  SELECT 
    af.*,
    CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
  FROM aki_flags af
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (
      (icd_version = '10' AND icd_code = 'J80')
      OR (icd_version = '9' AND icd_code IN ('518.5', '518.81', '518.82', '518.84'))
    )
  ) ards ON af.subject_id = ards.subject_id AND af.hadm_id = ards.hadm_id
)
SELECT 
  COUNT(*) AS cohort_size,
  SAFE_DIVIDE(
    COUNTIF(dod IS NOT NULL AND DATE_DIFF(dod, DATE(admittime), DAY) <= 30),
    COUNT(*)
  ) * 100 AS thirty_day_mortality_rate,
  SAFE_DIVIDE(SUM(has_aki), COUNT(*)) * 100 AS aki_rate,
  SAFE_DIVIDE(SUM(has_ards), COUNT(*)) * 100 AS ards_rate,
  APPROX_QUANTILES(risk_score, 4)[OFFSET(1)] AS composite_risk_25th_percentile,
  APPROX_QUANTILES(risk_score, 4)[OFFSET(2)] AS composite_risk_50th_percentile,
  APPROX_QUANTILES(risk_score, 4)[OFFSET(3)] AS composite_risk_75th_percentile,
  APPROX_QUANTILES(
    CASE WHEN dod IS NOT NULL AND DATE_DIFF(dod, DATE(admittime), DAY) <= 30 
         THEN DATE_DIFF(dod, DATE(admittime), DAY) 
    END,
    2
  )[OFFSET(1)] AS median_survival_days_decedents
FROM ards_flags;