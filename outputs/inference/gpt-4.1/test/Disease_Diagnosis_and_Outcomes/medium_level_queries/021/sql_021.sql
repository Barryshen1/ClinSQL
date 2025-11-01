WITH cohort AS (
  -- Step 1: Get male patients age 60-70 with postoperative complications
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND (
      -- ICD-9: 998.x
      (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^998[0-9]'))
      -- ICD-10: T81.x
      OR (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^T81'))
    )
),

icu_status AS (
  -- Step 2: Flag ICU admissions
  SELECT DISTINCT
    hadm_id,
    1 AS is_icu
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

charlson_map AS (
  -- Step 4: Map ICD codes to Charlson categories (simplified for demonstration)
  SELECT
    icd_code,
    icd_version,
    CASE
      -- Myocardial infarction
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^410')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I21')) THEN 'MI'
      -- Congestive heart failure
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50')) THEN 'CHF'
      -- Peripheral vascular disease
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^4439')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I73')) THEN 'PVD'
      -- Cerebrovascular disease
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^430|^431|^432|^433|^434|^435|^436')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I60|^I61|^I62|^I63|^I64')) THEN 'CVD'
      -- Dementia
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^290')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^F00|^F01|^F02|^F03')) THEN 'Dementia'
      -- Chronic pulmonary disease
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^490|^491|^492|^493|^494|^495|^496')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J40|^J41|^J42|^J43|^J44|^J45|^J47')) THEN 'Pulmonary'
      -- Rheumatic disease
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^446|^710|^714')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^M05|^M06|^M32|^M33|^M34')) THEN 'Rheumatic'
      -- Peptic ulcer disease
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^531|^532|^533|^534')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^K25|^K26|^K27|^K28')) THEN 'PUD'
      -- Mild liver disease
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^5712|^5714|^5715|^5716')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^K73|^K74')) THEN 'MildLiver'
      -- Diabetes without complication
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^2500|^2501|^2502|^2503')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E10|^E11|^E12|^E13|^E14')) THEN 'Diabetes'
      -- Diabetes with complication
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^2504|^2505|^2506|^2507|^2508|^2509')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E102|^E112|^E122|^E132|^E142')) THEN 'DiabComp'
      -- Hemiplegia or paraplegia
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^342|^343|^344')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^G81|^G82')) THEN 'Paraplegia'
      -- Renal disease
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^582|^583|^584|^585|^586|^588')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N18|^N19')) THEN 'Renal'
      -- Any malignancy
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^140|^141|^142|^143|^144|^145|^146|^147|^148|^149|^150|^151|^152|^153|^154|^155|^156|^157|^158|^159|^160|^161|^162|^163|^164|^165|^170|^171|^172|^174|^175|^176|^179|^180|^181|^182|^183|^184|^185|^186|^187|^188|^189|^190|^191|^192|^193|^194|^195|^196|^197|^198|^199')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^C')) THEN 'Malignancy'
      -- Moderate/severe liver disease
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^5722|^5723|^5724|^5728')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^K72|^K76')) THEN 'SevereLiver'
      -- Metastatic solid tumor
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^196|^197|^198|^199')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^C77|^C78|^C79|^C80')) THEN 'Metastatic'
      -- AIDS/HIV
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^042|^043|^044')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^B20|^B21|^B22|^B24')) THEN 'AIDS'
      ELSE NULL
    END AS charlson_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),

charlson_score AS (
  -- Step 4: Calculate Charlson score per admission (simplified weights)
  SELECT
    diag.hadm_id,
    COUNT(DISTINCT charlson_category) AS charlson_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    JOIN charlson_map cm
      ON diag.icd_code = cm.icd_code AND diag.icd_version = cm.icd_version
  WHERE
    cm.charlson_category IS NOT NULL
  GROUP BY
    diag.hadm_id
),

final_cohort AS (
  -- Step 3: Merge all info and categorize LOS/Charlson
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.hospital_expire_flag,
    IFNULL(i.is_icu, 0) AS is_icu,
    SAFE_CAST(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS INT64) AS los_days,
    cs.charlson_count,
    CASE
      WHEN SAFE_CAST(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS INT64) BETWEEN 1 AND 3 THEN '1-3'
      WHEN SAFE_CAST(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS INT64) BETWEEN 4 AND 7 THEN '4-7'
      WHEN SAFE_CAST(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS INT64) >= 8 THEN '>=8'
      ELSE NULL
    END AS los_category,
    CASE
      WHEN cs.charlson_count <= 3 THEN '<=3'
      WHEN cs.charlson_count BETWEEN 4 AND 5 THEN '4-5'
      WHEN cs.charlson_count > 5 THEN '>5'
      ELSE NULL
    END AS charlson_category,
    -- Time to death in days (for expired patients)
    CASE
      WHEN c.hospital_expire_flag = 1 AND c.deathtime IS NOT NULL
        THEN SAFE_CAST(TIMESTAMP_DIFF(c.deathtime, c.admittime, DAY) AS INT64)
      ELSE NULL
    END AS time_to_death_days
  FROM
    cohort c
    LEFT JOIN icu_status i ON c.hadm_id = i.hadm_id
    LEFT JOIN charlson_score cs ON c.hadm_id = cs.hadm_id
  WHERE
    SAFE_CAST(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS INT64) IS NOT NULL
    AND cs.charlson_count IS NOT NULL
    AND (
      CASE
        WHEN SAFE_CAST(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS INT64) BETWEEN 1 AND 3 THEN '1-3'
        WHEN SAFE_CAST(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS INT64) BETWEEN 4 AND 7 THEN '4-7'
        WHEN SAFE_CAST(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS INT64) >= 8 THEN '>=8'
        ELSE NULL
      END
    ) IS NOT NULL
    AND (
      CASE
        WHEN cs.charlson_count <= 3 THEN '<=3'
        WHEN cs.charlson_count BETWEEN 4 AND 5 THEN '4-5'
        WHEN cs.charlson_count > 5 THEN '>5'
        ELSE NULL
      END
    ) IS NOT NULL
)

-- Step 6: Group and report, fixing median calculation
SELECT
  icu_status,
  los_category,
  charlson_category,
  N,
  in_hospital_mortality_percent,
  -- Extract median from quantiles array
  time_to_death_quantiles[OFFSET(1)] AS median_time_to_death_days
FROM (
  SELECT
    CASE WHEN is_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    los_category,
    charlson_category,
    COUNT(*) AS N,
    ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_percent,
    APPROX_QUANTILES(time_to_death_days, 2) AS time_to_death_quantiles, -- array: [min, median, max]
  FROM
    final_cohort
  GROUP BY
    icu_status,
    los_category,
    charlson_category
)
ORDER BY
  icu_status,
  los_category,
  charlson_category;