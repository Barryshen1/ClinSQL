WITH aki_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE
    (UPPER(p.gender) IN ('M','MALE'))
    AND p.anchor_age BETWEEN 74 AND 84
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r"^584")) OR
          (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r"^N17"))
        )
    )
),

aki_risk_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.deathtime,
    -- ICD-9 flags
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^41[0-4]") THEN 1 ELSE 0 END) AS mi9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^428") THEN 1 ELSE 0 END) AS chf9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^250|^249") THEN 1 ELSE 0 END) AS dm9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^585") THEN 1 ELSE 0 END) AS ckd9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^570|^571|^572|^573|^574|^575|^576|^577|^578|^579") THEN 1 ELSE 0 END) AS liver9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^14[0-9]|^15[0-9]|^16[0-9]|^17[0-9]|^18[0-9]|^19[0-9]") THEN 1 ELSE 0 END) AS cancer9,
    -- ICD-10 flags
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^(I21|I22)") THEN 1 ELSE 0 END) AS mi10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^I50") THEN 1 ELSE 0 END) AS chf10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^E11|^E10|^250") THEN 1 ELSE 0 END) AS dm10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^N18|^N19|^N17") THEN 1 ELSE 0 END) AS ckd10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^K70|^K72|^K74") THEN 1 ELSE 0 END) AS liver10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^C[0-9]|^D[0-9]") THEN 1 ELSE 0 END) AS cancer10,
    -- ARDS flags (ICD-9/10)
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^(518\.5|5185|518\.82|51882)") THEN 1 ELSE 0 END) AS ards9,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^J80") THEN 1 ELSE 0 END) AS ards10
  FROM aki_cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d9
    ON d9.subject_id = c.subject_id AND d9.hadm_id = c.hadm_id AND d9.icd_version = 9
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d10
    ON d10.subject_id = c.subject_id AND d10.hadm_id = c.hadm_id AND d10.icd_version = 10
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.deathtime
),

aki_risk_score AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.deathtime,
    -- derived risk flags
    GREATEST(COALESCE(f.mi9,0), COALESCE(f.mi10,0)) AS has_mi,
    GREATEST(COALESCE(f.chf9,0), COALESCE(f.chf10,0)) AS has_chf,
    GREATEST(COALESCE(f.dm9,0), COALESCE(f.dm10,0)) AS has_dm,
    GREATEST(COALESCE(f.ckd9,0), COALESCE(f.ckd10,0)) AS has_ckd,
    GREATEST(COALESCE(f.liver9,0), COALESCE(f.liver10,0)) AS has_liver,
    GREATEST(COALESCE(f.cancer9,0), COALESCE(f.cancer10,0)) AS has_cancer,
    -- risk_score (weights: MI 1, CHF 1, DM 1, CKD 2, Liver 1, Cancer 2)
    (
      GREATEST(COALESCE(f.mi9,0), COALESCE(f.mi10,0)) * 1
      + GREATEST(COALESCE(f.chf9,0), COALESCE(f.chf10,0)) * 1
      + GREATEST(COALESCE(f.dm9,0), COALESCE(f.dm10,0)) * 1
      + GREATEST(COALESCE(f.ckd9,0), COALESCE(f.ckd10,0)) * 2
      + GREATEST(COALESCE(f.liver9,0), COALESCE(f.liver10,0)) * 1
      + GREATEST(COALESCE(f.cancer9,0), COALESCE(f.cancer10,0)) * 2
    ) AS risk_score,
    -- ARDS flags carried forward
    f.ards9 AS ards9,
    f.ards10 AS ards10,
    -- 30-day mortality indicator
    CASE WHEN a.deathtime IS NOT NULL AND DATE_DIFF(DATE(a.deathtime), DATE(a.admittime), DAY) <= 30 THEN 1 ELSE 0 END AS d30
  FROM aki_risk_flags AS f
  JOIN aki_cohort AS a
    ON a.subject_id = f.subject_id AND a.hadm_id = f.hadm_id
),

aki_final AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.admittime,
    r.dischtime,
    r.deathtime,
    r.has_mi,
    r.has_chf,
    r.has_dm,
    r.has_ckd,
    r.has_liver,
    r.has_cancer,
    r.risk_score,
    r.ards9,
    r.ards10,
    -- derive ARDS presence
    GREATEST(COALESCE(r.ards9,0), COALESCE(r.ards10,0)) AS has_ards,
    r.d30,
    -- survivor LOS (days) if the patient survived
    CASE WHEN r.deathtime IS NULL THEN DATE_DIFF(DATE(r.dischtime), DATE(r.admittime), DAY) END AS survivor_los_days
  FROM aki_risk_score AS r
),

-- 3) General population: all male inpatients, age 74–84 (no AKI filter) with ARDS flags
general_cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    -- ICD-9/10 flags for comorbidity (same as AKI path)
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^41[0-4]") THEN 1 ELSE 0 END) AS mi9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^428") THEN 1 ELSE 0 END) AS chf9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^250|^249") THEN 1 ELSE 0 END) AS dm9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^585") THEN 1 ELSE 0 END) AS ckd9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^570|^571|^572|^573|^574|^575|^576|^577|^578|^579") THEN 1 ELSE 0 END) AS liver9,
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^14[0-9]|^15[0-9]|^16[0-9]|^17[0-9]|^18[0-9]|^19[0-9]") THEN 1 ELSE 0 END) AS cancer9,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^(I21|I22)") THEN 1 ELSE 0 END) AS mi10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^I50") THEN 1 ELSE 0 END) AS chf10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^E11|^E10|^250") THEN 1 ELSE 0 END) AS dm10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^N18|^N19|^N17") THEN 1 ELSE 0 END) AS ckd10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^K70|^K72|^K74") THEN 1 ELSE 0 END) AS liver10,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^C[0-9]|^D[0-9]") THEN 1 ELSE 0 END) AS cancer10,
    -- ARDS flags
    MAX(CASE WHEN d9.icd_version = 9 AND REGEXP_CONTAINS(d9.icd_code, r"^(518\.5|5185|518\.82|51882)") THEN 1 ELSE 0 END) AS ards9,
    MAX(CASE WHEN d10.icd_version = 10 AND REGEXP_CONTAINS(d10.icd_code, r"^J80") THEN 1 ELSE 0 END) AS ards10
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d9
    ON d9.subject_id = a.subject_id AND d9.hadm_id = a.hadm_id AND d9.icd_version = 9
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d10
    ON d10.subject_id = a.subject_id AND d10.hadm_id = a.hadm_id AND d10.icd_version = 10
  WHERE (UPPER(p.gender) IN ('M','MALE'))
    AND p.anchor_age BETWEEN 74 AND 84
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.deathtime
),

general_risk AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    -- comorbidity flags (ICD-9/10)
    GREATEST(COALESCE(mi9,0), COALESCE(mi10,0)) AS has_mi,
    GREATEST(COALESCE(chf9,0), COALESCE(chf10,0)) AS has_chf,
    GREATEST(COALESCE(dm9,0), COALESCE(dm10,0)) AS has_dm,
    GREATEST(COALESCE(ckd9,0), COALESCE(ckd10,0)) AS has_ckd,
    GREATEST(COALESCE(liver9,0), COALESCE(liver10,0)) AS has_liver,
    GREATEST(COALESCE(cancer9,0), COALESCE(cancer10,0)) AS has_cancer,
    (GREATEST(COALESCE(mi9,0), COALESCE(mi10,0)) * 1
     + GREATEST(COALESCE(chf9,0), COALESCE(chf10,0)) * 1
     + GREATEST(COALESCE(dm9,0), COALESCE(dm10,0)) * 1
     + GREATEST(COALESCE(ckd9,0), COALESCE(ckd10,0)) * 2
     + GREATEST(COALESCE(liver9,0), COALESCE(liver10,0)) * 1
     + GREATEST(COALESCE(cancer9,0), COALESCE(cancer10,0)) * 2
    ) AS risk_score,
    -- ARDS flags carried forward
    ards9,
    ards10,
    GREATEST(COALESCE(ards9,0), COALESCE(ards10,0)) AS has_ards
  FROM general_cohort
)

, aki_medians AS (
  SELECT
    (quantiles[OFFSET(50)]) AS median_risk_aki,
    (quantiles[OFFSET(25)]) AS q1_aki,
    (quantiles[OFFSET(75)]) AS q3_aki
  FROM (
    SELECT APPROX_QUANTILES(risk_score, 101) AS quantiles
    FROM aki_risk_score
  )
)

, survivor_los_median_aki AS (
  SELECT quantiles[OFFSET(50)] AS survivor_los_median_aki
  FROM (
    SELECT APPROX_QUANTILES(survivor_los_days, 101) AS quantiles
    FROM aki_final
    WHERE survivor_los_days IS NOT NULL
  )
)

, general_medians AS (
  SELECT
    (quantiles[OFFSET(50)]) AS median_risk_general,
    (quantiles[OFFSET(25)]) AS q1_general,
    (quantiles[OFFSET(75)]) AS q3_general
  FROM (
    SELECT APPROX_QUANTILES(risk_score, 101) AS quantiles
    FROM general_risk
  )
)

, survivor_los_median_general AS (
  SELECT quantiles[OFFSET(50)] AS survivor_los_median_general
  FROM (
    SELECT APPROX_QUANTILES(survivor_los_days, 101) AS quantiles
    FROM (
      SELECT CASE WHEN deathtime IS NULL THEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) END AS survivor_los_days
      FROM general_cohort
      WHERE dischtime IS NOT NULL
    )
  )
)

, mort_sub AS (
  SELECT 100.0 * AVG(CASE WHEN d30 = 1 THEN 1 ELSE 0 END) AS thirty_day_mortality_aki
  FROM aki_final
)

, ards_rate_aki_sub AS (
  SELECT 100.0 * AVG(has_ards) AS ards_rate_aki
  FROM aki_final
)

-- 4) Final metrics: median risk (IQR), 30-day mortality, ARDS rate, survivor LOS
SELECT
  aki_medians.median_risk_aki,
  (aki_medians.q3_aki - aki_medians.q1_aki) AS iqr_risk_aki,
  mort_sub.thirty_day_mortality_aki,
  ards_rate_aki_sub.ards_rate_aki,
  survivor_los_aki.survivor_los_median_aki,
  general_medians.median_risk_general,
  survivor_los_general.survivor_los_median_general
FROM aki_medians
CROSS JOIN mort_sub
CROSS JOIN ards_rate_aki_sub
CROSS JOIN survivor_los_median_aki AS survivor_los_aki
CROSS JOIN general_medians
CROSS JOIN survivor_los_median_general AS survivor_los_general;