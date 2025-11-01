WITH
-- 1. Get male inpatients aged 74-84
male_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),

-- 2. Identify AKI admissions (ICD-9: 584.x, ICD-10: N17.x)
aki_admissions AS (
  SELECT DISTINCT
    mi.subject_id,
    mi.hadm_id
  FROM
    male_inpatients mi
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON mi.hadm_id = d.hadm_id
  WHERE
    (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^584'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N17'))
    )
),

-- 3. Identify ARDS admissions (ICD-9: 518.5, 518.82; ICD-10: J80)
ards_admissions AS (
  SELECT DISTINCT
    mi.subject_id,
    mi.hadm_id
  FROM
    male_inpatients mi
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON mi.hadm_id = d.hadm_id
  WHERE
    (
      (d.icd_version = 9 AND (d.icd_code = '5185' OR d.icd_code = '51882'))
      OR
      (d.icd_version = 10 AND d.icd_code = 'J80')
    )
),

-- 4. Get ICU stays for male inpatients
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN male_inpatients mi
      ON i.subject_id = mi.subject_id
      AND i.hadm_id = mi.hadm_id
),

-- 5. Find SOFA itemid(s)
sofa_itemids AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%sofa%'
),

-- 6. Get first SOFA score per ICU stay (FIXED)
sofa_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime AS first_charttime,
    c.valuenum AS first_sofa
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN icu_stays i
      ON c.subject_id = i.subject_id
      AND c.hadm_id = i.hadm_id
      AND c.stay_id = i.stay_id
    JOIN sofa_itemids s
      ON c.itemid = s.itemid
  WHERE
    c.valuenum IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime ASC) = 1
),

-- 7. AKI cohort with SOFA scores
aki_cohort AS (
  SELECT
    mi.*,
    ss.first_sofa
  FROM
    aki_admissions aki
    JOIN male_inpatients mi
      ON aki.subject_id = mi.subject_id
      AND aki.hadm_id = mi.hadm_id
    LEFT JOIN icu_stays icu
      ON mi.subject_id = icu.subject_id
      AND mi.hadm_id = icu.hadm_id
    LEFT JOIN sofa_scores ss
      ON icu.stay_id = ss.stay_id
),

-- 8. General cohort with SOFA scores
general_cohort AS (
  SELECT
    mi.*,
    ss.first_sofa
  FROM
    male_inpatients mi
    LEFT JOIN icu_stays icu
      ON mi.subject_id = icu.subject_id
      AND mi.hadm_id = icu.hadm_id
    LEFT JOIN sofa_scores ss
      ON icu.stay_id = ss.stay_id
),

-- 9. Calculate 30-day mortality for AKI cohort
aki_mortality AS (
  SELECT
    COUNT(*) AS aki_total,
    COUNTIF(
      (
        mi.hospital_expire_flag = 1
        OR (mi.dod IS NOT NULL AND DATETIME_DIFF(mi.dod, mi.admittime, DAY) <= 30)
      )
    ) AS aki_30day_deaths
  FROM
    aki_cohort mi
),

-- 10. ARDS rates
aki_ards AS (
  SELECT
    COUNT(*) AS aki_total,
    COUNTIF(
      EXISTS (
        SELECT 1 FROM ards_admissions aa
        WHERE aa.subject_id = mi.subject_id AND aa.hadm_id = mi.hadm_id
      )
    ) AS aki_ards_cases
  FROM
    aki_cohort mi
),
general_ards AS (
  SELECT
    COUNT(*) AS gen_total,
    COUNTIF(
      EXISTS (
        SELECT 1 FROM ards_admissions aa
        WHERE aa.subject_id = mi.subject_id AND aa.hadm_id = mi.hadm_id
      )
    ) AS gen_ards_cases
  FROM
    general_cohort mi
),

-- 11. Survivor LOS
aki_survivor_los AS (
  SELECT
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[50] AS median_los,
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[25] AS q1_los,
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[75] AS q3_los
  FROM
    aki_cohort
  WHERE
    hospital_expire_flag = 0
),
general_survivor_los AS (
  SELECT
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[50] AS median_los,
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[25] AS q1_los,
    APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 100)[75] AS q3_los
  FROM
    general_cohort
  WHERE
    hospital_expire_flag = 0
),

-- 12. SOFA score stats
aki_sofa_stats AS (
  SELECT
    APPROX_QUANTILES(first_sofa, 100)[50] AS median_sofa,
    APPROX_QUANTILES(first_sofa, 100)[25] AS q1_sofa,
    APPROX_QUANTILES(first_sofa, 100)[75] AS q3_sofa
  FROM
    aki_cohort
  WHERE
    first_sofa IS NOT NULL
),
general_sofa_stats AS (
  SELECT
    ARRAY_AGG(first_sofa IGNORE NULLS) AS sofa_scores
  FROM
    general_cohort
  WHERE
    first_sofa IS NOT NULL
),

-- 13. Risk percentile: what percentile is AKI median SOFA in general cohort?
aki_risk_percentile AS (
  SELECT
    aki_stats.median_sofa,
    (
      SELECT
        COUNTIF(score < aki_stats.median_sofa) / COUNT(*) * 100
      FROM
        UNNEST(gen_stats.sofa_scores) AS score
    ) AS risk_percentile
  FROM
    aki_sofa_stats aki_stats,
    general_sofa_stats gen_stats
)

-- Final output
SELECT
  -- AKI cohort
  aki_stats.median_sofa AS aki_median_sofa,
  aki_stats.q1_sofa AS aki_q1_sofa,
  aki_stats.q3_sofa AS aki_q3_sofa,
  aki_mort.aki_total AS aki_total,
  aki_mort.aki_30day_deaths AS aki_30day_deaths,
  SAFE_DIVIDE(aki_mort.aki_30day_deaths, aki_mort.aki_total) AS aki_30day_mortality_rate,
  aki_ards.aki_ards_cases AS aki_ards_cases,
  SAFE_DIVIDE(aki_ards.aki_ards_cases, aki_ards.aki_total) AS aki_ards_rate,
  aki_surv.median_los AS aki_survivor_median_los,
  aki_surv.q1_los AS aki_survivor_q1_los,
  aki_surv.q3_los AS aki_survivor_q3_los,
  aki_risk.risk_percentile AS aki_median_sofa_percentile_in_general,

  -- General cohort
  gen_ards.gen_ards_cases AS general_ards_cases,
  SAFE_DIVIDE(gen_ards.gen_ards_cases, gen_ards.gen_total) AS general_ards_rate,
  gen_surv.median_los AS general_survivor_median_los,
  gen_surv.q1_los AS general_survivor_q1_los,
  gen_surv.q3_los AS general_survivor_q3_los

FROM
  aki_sofa_stats aki_stats,
  aki_mortality aki_mort,
  aki_ards aki_ards,
  aki_survivor_los aki_surv,
  aki_risk_percentile aki_risk,
  general_ards gen_ards,
  general_survivor_los gen_surv;