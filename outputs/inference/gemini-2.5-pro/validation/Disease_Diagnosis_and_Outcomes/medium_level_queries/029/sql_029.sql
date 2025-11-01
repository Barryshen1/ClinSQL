WITH
-- Step 1: Calculate the Charlson Comorbidity Index from scratch using ICD codes.
-- This replaces the inaccessible `mimiciv_derived.charlson` table.
charlson AS (
  SELECT
    hadm_id,
    -- Sum of weights for each condition, applying hierarchical rules
    (mi) + (chf) + (pvd) + (cevd) + (dementia) + (cpd) + (rheumd) + (pud)
    + GREATEST(diab_comp * 2, diab_no_comp * 1) -- Diabetes score (0, 1, or 2)
    + GREATEST(sev_liver * 3, mild_liver * 1) -- Liver disease score (0, 1, or 3)
    + GREATEST(mets * 6, malignant * 2)       -- Cancer score (0, 2, or 6)
    + (plegia * 2) + (rendis * 2) + (aids * 6)
    AS charlson_comorbidity_index
  FROM (
    -- Flag the presence of each comorbidity for each hospital admission
    SELECT
      hadm_id,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('410', '412')
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') THEN 1 ELSE 0 END) AS mi,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50' THEN 1 ELSE 0 END) AS chf,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('440', '441') OR SUBSTR(icd_code, 1, 4) = '443.9')
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I70', 'I71') OR SUBSTR(icd_code, 1, 4) = 'I73.9') THEN 1 ELSE 0 END) AS pvd,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I69' THEN 1 ELSE 0 END) AS cevd,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '290'
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('F00','F01','F02','F03') OR SUBSTR(icd_code, 1, 4) = 'G30') THEN 1 ELSE 0 END) AS dementia,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '505'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47' THEN 1 ELSE 0 END) AS cpd,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '714'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'M05' THEN 1 ELSE 0 END) AS rheumd,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '531' AND '534'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'K25' AND 'K28' THEN 1 ELSE 0 END) AS pud,
      MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '571' OR SUBSTR(icd_code, 1, 4) IN ('573.3', '573.4'))
                 OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('K70', 'K73', 'K74') OR SUBSTR(icd_code, 1, 4) = 'K76.0') THEN 1 ELSE 0 END) AS mild_liver,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('572.2', '572.3', '572.4')
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('K72') THEN 1 ELSE 0 END) AS sev_liver,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('250.0', '250.1', '250.2', '250.3')
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E10.0','E10.1','E10.9','E11.0','E11.1','E11.9') THEN 1 ELSE 0 END) AS diab_no_comp,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('250.4', '250.5', '250.6', '250.7')
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 4) IN ('E10.2','E10.3','E10.4','E10.5','E10.7','E11.2','E11.3','E11.4','E11.5','E11.7') THEN 1 ELSE 0 END) AS diab_comp,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('342', '343')
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('G81', 'G82') THEN 1 ELSE 0 END) AS plegia,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '585'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'N18' THEN 1 ELSE 0 END) AS rendis,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '195'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C76' THEN 1 ELSE 0 END) AS malignant,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '196' AND '199'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'C77' AND 'C80' THEN 1 ELSE 0 END) AS mets,
      MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '042'
                 OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('B20', 'B21', 'B22', 'B24') THEN 1 ELSE 0 END) AS aids
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
  )
),

-- Step 2: Identify all hospital admissions with a diagnosis of sepsis or septic shock.
-- Assign each admission to a group: 'Septic Shock' or 'Sepsis (without shock)'.
sepsis_admissions AS (
  SELECT
    hadm_id,
    CASE
      WHEN MAX(CASE
          -- Septic shock codes (ICD-9 and ICD-10)
          WHEN diag.icd_code IN ('785.52', 'R65.21')
          THEN 1
          ELSE 0
        END) = 1
      THEN 'Septic Shock'
      ELSE 'Sepsis (without shock)'
    END AS sepsis_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  WHERE
    -- Filter for admissions that have at least one sepsis-related code
    diag.icd_code IN ('995.91', '995.92', 'R65.20', -- Sepsis
                      '785.52', 'R65.21'  -- Septic Shock
                      )
    OR diag.icd_code LIKE '038%' -- Septicemia (ICD-9)
    OR diag.icd_code LIKE 'A40%' -- Streptococcal sepsis (ICD-10)
    OR diag.icd_code LIKE 'A41%' -- Other sepsis (ICD-10)
  GROUP BY
    hadm_id
),

-- Step 3: Build the main cohort by filtering patients by age and gender,
-- join with the sepsis admissions and Charlson scores, and create LOS/Charlson categories.
categorized_cohort AS (
  SELECT
    adm.hadm_id,
    sep.sepsis_group,
    adm.hospital_expire_flag,
    -- Categorize Length of Stay (LOS)
    CASE
      WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) <= 7 THEN '≤7 days'
      ELSE '>7 days'
    END AS los_category,
    -- Categorize Charlson Comorbidity Index
    CASE
      WHEN ch.charlson_comorbidity_index <= 3 THEN '≤3'
      WHEN ch.charlson_comorbidity_index BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN sepsis_admissions AS sep
    ON adm.hadm_id = sep.hadm_id
  INNER JOIN charlson AS ch -- Use the newly created Charlson CTE
    ON adm.hadm_id = ch.hadm_id
  WHERE
    pat.gender = 'F'
    -- More precise age calculation: age at time of admission
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 57 AND 67
),

-- Step 4: Calculate mortality rates for each combination of categories.
group_summary AS (
  SELECT
    sepsis_group,
    los_category,
    charlson_category,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS mortality_count,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate
  FROM
    categorized_cohort
  GROUP BY
    sepsis_group,
    los_category,
    charlson_category
),

-- Step 5: Pivot the data to have sepsis and septic shock mortality side-by-side
-- for each LOS/Charlson category to facilitate comparison.
pivoted_summary AS (
  SELECT
    los_category,
    charlson_category,
    MAX(CASE WHEN sepsis_group = 'Sepsis (without shock)' THEN mortality_rate END) AS mortality_rate_sepsis,
    MAX(CASE WHEN sepsis_group = 'Septic Shock' THEN mortality_rate END) AS mortality_rate_shock,
    SUM(CASE WHEN sepsis_group = 'Sepsis (without shock)' THEN total_patients END) AS n_sepsis,
    SUM(CASE WHEN sepsis_group = 'Septic Shock' THEN total_patients END) AS n_shock
  FROM
    group_summary
  GROUP BY
    los_category,
    charlson_category
)

-- Final Step: Present the results and calculate absolute and relative differences.
SELECT
  los_category AS length_of_stay,
  charlson_category AS charlson_score_group,
  -- Cohort sizes
  COALESCE(n_sepsis, 0) AS count_sepsis_without_shock,
  COALESCE(n_shock, 0) AS count_septic_shock,
  -- Mortality Rates (%)
  ROUND(COALESCE(mortality_rate_sepsis, 0) * 100, 2) AS mortality_pct_sepsis_without_shock,
  ROUND(COALESCE(mortality_rate_shock, 0) * 100, 2) AS mortality_pct_septic_shock,
  -- Differences
  ROUND((COALESCE(mortality_rate_shock, 0) - COALESCE(mortality_rate_sepsis, 0)) * 100, 2) AS absolute_difference_pp,
  ROUND(SAFE_DIVIDE(
    COALESCE(mortality_rate_shock, 0) - COALESCE(mortality_rate_sepsis, 0),
    mortality_rate_sepsis
  ) * 100, 2) AS relative_difference_pct
FROM
  pivoted_summary
ORDER BY
  -- Custom sort order for readability
  CASE
    WHEN los_category = '≤7 days' THEN 1
    ELSE 2
  END,
  CASE
    WHEN charlson_category = '≤3' THEN 1
    WHEN charlson_category = '4-5' THEN 2
    ELSE 3
  END;