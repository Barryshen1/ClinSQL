WITH gib_codes AS (
  -- This CTE flags hospital admissions with diagnoses of Upper or Lower GI Bleeds
  -- using specific ICD-9 and ICD-10 codes to avoid ambiguity.
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN
          -- Upper GI bleed ICD-9
          (
            icd_version = 9 AND (
              icd_code LIKE '456.0%' OR icd_code LIKE '456.20%' -- Esophageal varices with bleeding
              OR icd_code LIKE '530.7%' -- Mallory-weiss syndrome
              OR icd_code LIKE '531.0%' OR icd_code LIKE '531.2%' OR icd_code LIKE '531.4%' OR icd_code LIKE '531.6%' -- Gastric ulcer with hemorrhage/perf
              OR icd_code LIKE '532.0%' OR icd_code LIKE '532.2%' OR icd_code LIKE '532.4%' OR icd_code LIKE '532.6%' -- Duodenal ulcer with hemorrhage/perf
              OR icd_code LIKE '533.0%' OR icd_code LIKE '533.2%' OR icd_code LIKE '533.4%' OR icd_code LIKE '533.6%' -- Peptic ulcer with hemorrhage/perf
              OR icd_code LIKE '534.0%' OR icd_code LIKE '534.2%' OR icd_code LIKE '534.4%' OR icd_code LIKE '534.6%' -- Gastrojejunal ulcer with hemorrhage/perf
              OR icd_code IN ('578.0', '578.1') -- Hematemesis, Melena
            )
          )
          OR
          -- Upper GI bleed ICD-10
          (
            icd_version = 10 AND (
              icd_code LIKE 'I85.01%' OR icd_code LIKE 'I85.11%' -- Esophageal varices with bleeding
              OR icd_code LIKE 'K22.11%' -- Ulcer of esophagus with bleeding
              OR icd_code LIKE 'K22.6%' -- GE junction tear with hemorrhage
              OR icd_code LIKE 'K25.0%' OR icd_code LIKE 'K25.1%' OR icd_code LIKE 'K25.2%' OR icd_code LIKE 'K25.4%' OR icd_code LIKE 'K25.5%' OR icd_code LIKE 'K25.6%' -- Gastric ulcer
              OR icd_code LIKE 'K26.0%' OR icd_code LIKE 'K26.1%' OR icd_code LIKE 'K26.2%' OR icd_code LIKE 'K26.4%' OR icd_code LIKE 'K26.5%' OR icd_code LIKE 'K26.6%' -- Duodenal ulcer
              OR icd_code LIKE 'K27.0%' OR icd_code LIKE 'K27.1%' OR icd_code LIKE 'K27.2%' OR icd_code LIKE 'K27.4%' OR icd_code LIKE 'K27.5%' OR icd_code LIKE 'K27.6%' -- Peptic ulcer
              OR icd_code LIKE 'K28.0%' OR icd_code LIKE 'K28.1%' OR icd_code LIKE 'K28.2%' OR icd_code LIKE 'K28.4%' OR icd_code LIKE 'K28.5%' OR icd_code LIKE 'K28.6%' -- Gastrojejunal ulcer
              OR icd_code LIKE 'K29.01%' -- Acute gastritis with bleeding
              OR icd_code IN ('K92.0', 'K92.1') -- Hematemesis, Melena
            )
          )
          THEN 1
        ELSE 0
      END
    ) AS has_ugib,
    MAX(
      CASE
        WHEN
          -- Lower GI bleed ICD-9
          (
            icd_version = 9 AND (
              icd_code LIKE '562.02%' OR icd_code LIKE '562.03%' -- Diverticula/osis small intestine w hemorrhage
              OR icd_code LIKE '562.11%' OR icd_code LIKE '562.13%' -- Diverticula/itis colon w hemorrhage
              OR icd_code = '569.3' -- Hemorrhage of rectum and anus
              OR icd_code = '569.85' -- Angiodysplasia of intestine with hemorrhage
            )
          )
          OR
          -- Lower GI bleed ICD-10
          (
            icd_version = 10 AND (
              icd_code LIKE 'K55.21%' -- Angiodysplasia of colon with bleeding
              OR icd_code LIKE 'K57.01%' OR icd_code LIKE 'K57.11%' OR icd_code LIKE 'K57.21%' OR icd_code LIKE 'K57.31%' OR icd_code LIKE 'K57.41%' OR icd_code LIKE 'K57.51%' OR icd_code LIKE 'K57.81%' OR icd_code LIKE 'K57.91%' -- Diverticular disease with hemorrhage
              OR icd_code = 'K62.5' -- Hemorrhage of anus and rectum
            )
          )
          THEN 1
        ELSE 0
      END
    ) AS has_lgib
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
cohort_base AS (
  -- This CTE defines the base cohort of patients, calculates LOS,
  -- and determines ICU status flags.
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    CASE
      WHEN g.has_ugib = 1
      THEN 'Upper'
      ELSE 'Lower'
    END AS gi_bleed_type,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 > 0 AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 <= 2
      THEN '1-2 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 > 2 AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 <= 5
      THEN '3-5 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 > 5 AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 <= 9
      THEN '6-9 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 > 9
      THEN '>=10 days'
      ELSE NULL
    END AS los_category,
    MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS was_in_icu,
    MAX(CASE WHEN icu.intime < DATETIME_ADD(a.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN gib_codes AS g
    ON a.hadm_id = g.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND (g.has_ugib = 1 OR g.has_lgib = 1) -- Must have one of the diagnoses
    AND NOT (g.has_ugib = 1 AND g.has_lgib = 1) -- Exclude if both are present
    AND a.dischtime > a.admittime -- Ensure valid LOS > 0
  GROUP BY
    a.hadm_id,
    a.hospital_expire_flag,
    gi_bleed_type,
    los_category,
    a.admittime,
    a.dischtime
),
icu_rates AS (
  -- This CTE calculates the overall ICU admission rate per GI bleed type.
  SELECT
    gi_bleed_type,
    ROUND(AVG(was_in_icu) * 100, 2) AS overall_icu_admission_rate_pct
  FROM cohort_base
  GROUP BY
    gi_bleed_type
),
mortality_stats AS (
  -- This CTE calculates the stratified mortality statistics.
  SELECT
    gi_bleed_type,
    los_category,
    CASE WHEN icu_day1 = 1 THEN 'Yes' ELSE 'No' END AS admitted_to_icu_day1,
    COUNT(hadm_id) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct
  FROM cohort_base
  WHERE
    los_category IS NOT NULL
  GROUP BY
    gi_bleed_type,
    los_category,
    admitted_to_icu_day1
)
-- Final SELECT joins the ICU rates with the mortality stats for a combined report.
SELECT
  ms.gi_bleed_type,
  ir.overall_icu_admission_rate_pct,
  ms.los_category,
  ms.admitted_to_icu_day1,
  ms.total_patients,
  ms.deaths,
  ms.mortality_pct
FROM mortality_stats AS ms
JOIN icu_rates AS ir
  ON ms.gi_bleed_type = ir.gi_bleed_type
ORDER BY
  ms.gi_bleed_type,
  CASE
    WHEN ms.los_category = '1-2 days'
    THEN 1
    WHEN ms.los_category = '3-5 days'
    THEN 2
    WHEN ms.los_category = '6-9 days'
    THEN 3
    WHEN ms.los_category = '>=10 days'
    THEN 4
  END,
  ms.admitted_to_icu_day1 DESC;