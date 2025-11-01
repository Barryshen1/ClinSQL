WITH
  -- Step 1: Create a base cohort of male patients aged 64-74 at admission
  base_admissions AS (
    SELECT
      p.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      p.dod
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON p.subject_id = adm.subject_id
    WHERE
      p.gender = 'M'
      AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 64 AND 74
  ),
  -- Step 2: Filter the cohort for admissions with an Upper GI Bleed diagnosis
  ugib_admissions AS (
    SELECT DISTINCT
      b.hadm_id
    FROM base_admissions AS b
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON b.hadm_id = dx.hadm_id
    WHERE
      -- ICD-9 codes for UGIB (no decimals in MIMIC-IV)
      dx.icd_code IN ('5780', '5781', '5789') -- General hemorrhage
      OR dx.icd_code LIKE '5310%' -- Gastric ulcer w/ hemorrhage
      OR dx.icd_code LIKE '5320%' -- Duodenal ulcer w/ hemorrhage
      OR dx.icd_code LIKE '5330%' -- Peptic ulcer w/ hemorrhage
      OR dx.icd_code LIKE '5340%' -- Gastrojejunal ulcer w/ hemorrhage
      -- ICD-10 codes for UGIB
      OR dx.icd_code IN ('K920', 'K921', 'K922') -- General hemorrhage
      OR dx.icd_code LIKE 'K250%' -- Acute gastric ulcer w/ hemorrhage
      OR dx.icd_code LIKE 'K254%' -- Chronic gastric ulcer w/ hemorrhage
      OR dx.icd_code LIKE 'K260%' -- Acute duodenal ulcer w/ hemorrhage
      OR dx.icd_code LIKE 'K264%' -- Chronic duodenal ulcer w/ hemorrhage
      OR dx.icd_code LIKE 'K270%' -- Acute peptic ulcer w/ hemorrhage
      OR dx.icd_code LIKE 'K274%' -- Chronic peptic ulcer w/ hemorrhage
  ),
  -- Step 3: Calculate diagnosis count, major complication flag, mortality, and LOS for each admission
  admission_features AS (
    SELECT
      ugib.hadm_id,
      COUNT(DISTINCT dx.icd_code) AS diagnosis_count,
      MAX(
        CASE
          WHEN
            -- ICD-9 for Shock
            dx.icd_code LIKE '7855%'
            -- ICD-10 for Shock
            OR dx.icd_code LIKE 'R57%'
            -- ICD-9 for AKI
            OR dx.icd_code LIKE '584%'
            -- ICD-10 for AKI
            OR dx.icd_code LIKE 'N17%'
            THEN 1
          ELSE 0
        END
      ) AS major_complication_flag,
      MAX(
        CASE
          WHEN b.dod IS NOT NULL AND DATETIME_DIFF(b.dod, b.admittime, DAY) <= 30
            THEN 1
          ELSE 0
        END
      ) AS thirty_day_mortality,
      MAX(DATETIME_DIFF(b.dischtime, b.admittime, HOUR)) / 24.0 AS los_days
    FROM ugib_admissions AS ugib
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON ugib.hadm_id = dx.hadm_id
    INNER JOIN base_admissions AS b
      ON ugib.hadm_id = b.hadm_id
    GROUP BY
      ugib.hadm_id
  ),
  -- Step 4: Calculate composite risk score and stratify into quintiles
  quintiled_data AS (
    SELECT
      hadm_id,
      thirty_day_mortality,
      major_complication_flag,
      los_days,
      (diagnosis_count + 20 * major_complication_flag) AS composite_risk_score,
      NTILE(5) OVER (ORDER BY (diagnosis_count + 20 * major_complication_flag)) AS risk_quintile
    FROM admission_features
  )
-- Step 5: Aggregate metrics by quintile
SELECT
  risk_quintile,
  COUNT(hadm_id) AS n,
  AVG(composite_risk_score) AS mean_score,
  AVG(thirty_day_mortality) * 100 AS `thirty_day_mortality_%`,
  AVG(major_complication_flag) * 100 AS `major_complication_%`,
  APPROX_QUANTILES(
    CASE WHEN thirty_day_mortality = 0 THEN los_days ELSE NULL END, 100
  )[OFFSET(50)] AS median_los_among_survivors
FROM quintiled_data
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;