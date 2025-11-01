WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS INT64) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

diagnosis_flags AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    -- STEMI flag
    MAX(
      CASE
        -- ICD-10 STEMI
        WHEN d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I21[.]0|^I21[.]1|^I21[.]2|^I21[.]3|^I22[.]0|^I22[.]1|^I22[.]2')
          THEN 1
        -- ICD-9 STEMI
        WHEN d.icd_version = 9 AND (
          REGEXP_CONTAINS(d.icd_code, r'^410[.]0|^410[.]1|^410[.]2|^410[.]3|^410[.]4|^410[.]5|^410[.]6|^410[.]8')
        )
          THEN 1
        ELSE 0
      END
    ) AS is_stemi,
    -- NSTEMI flag
    MAX(
      CASE
        -- ICD-10 NSTEMI
        WHEN d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I21[.]4|^I22[.]8|^I22[.]9')
          THEN 1
        -- ICD-9 NSTEMI
        WHEN d.icd_version = 9 AND (
          REGEXP_CONTAINS(d.icd_code, r'^410[.]7|^410[.]9')
        )
          THEN 1
        ELSE 0
      END
    ) AS is_nstemi,
    -- CKD flag
    MAX(
      CASE
        -- ICD-10 CKD
        WHEN d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N18')
          THEN 1
        -- ICD-9 CKD
        WHEN d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^585')
          THEN 1
        ELSE 0
      END
    ) AS has_ckd,
    -- Diabetes flag
    MAX(
      CASE
        -- ICD-10 Diabetes
        WHEN d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E1[0-4]')
          THEN 1
        -- ICD-9 Diabetes
        WHEN d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250')
          THEN 1
        ELSE 0
      END
    ) AS has_diabetes,
    -- Elixhauser comorbidity count (excluding STEMI/NSTEMI, CKD, diabetes)
    COUNT(DISTINCT
      CASE
        -- Example: Use a subset of Elixhauser codes (see published lists)
        -- Exclude STEMI/NSTEMI, CKD, diabetes
        WHEN (
          -- CHF
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50')) OR
          (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
        ) THEN 'CHF'
        WHEN (
          -- Hypertension
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I10|^I11|^I12|^I13|^I15')) OR
          (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^401|^402|^403|^404|^405'))
        ) THEN 'HTN'
        WHEN (
          -- COPD
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J44')) OR
          (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^496'))
        ) THEN 'COPD'
        WHEN (
          -- Cancer
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^C')) OR
          (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^140|^141|^142|^143|^144|^145|^146|^147|^148|^149|^150|^151|^152|^153|^154|^155|^156|^157|^158|^159|^160|^161|^162|^163|^164|^165|^166|^167|^168|^169|^170|^171|^172|^173|^174|^175|^176|^177|^178|^179|^180|^181|^182|^183|^184|^185|^186|^187|^188|^189|^190|^191|^192|^193|^194|^195|^196|^197|^198|^199'))
        ) THEN 'Cancer'
        -- Add more Elixhauser groups as needed
        ELSE NULL
      END
    ) AS elixhauser_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY
    d.subject_id, d.hadm_id
),

final_cohort AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.los_days,
    CASE
      WHEN df.is_stemi = 1 THEN 'STEMI'
      WHEN df.is_nstemi = 1 THEN 'NSTEMI'
      ELSE NULL
    END AS infarct_type,
    c.hospital_expire_flag,
    df.has_ckd,
    df.has_diabetes,
    df.elixhauser_count
  FROM
    cohort c
    JOIN diagnosis_flags df
      ON c.subject_id = df.subject_id AND c.hadm_id = df.hadm_id
  WHERE
    (df.is_stemi = 1 OR df.is_nstemi = 1)
),

binned_cohort AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
      WHEN los_days >= 10 THEN '>=10'
      ELSE NULL
    END AS los_bin,
    CASE
      WHEN elixhauser_count <= 1 THEN '0-1'
      WHEN elixhauser_count = 2 THEN '2'
      WHEN elixhauser_count >= 3 THEN '>=3'
      ELSE NULL
    END AS comorbidity_bin
  FROM
    final_cohort
  WHERE
    los_days IS NOT NULL
)

SELECT
  infarct_type,
  los_bin,
  comorbidity_bin,
  COUNT(*) AS N,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS mortality_pct,
  ROUND(100 * SUM(CASE WHEN has_ckd = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS ckd_pct,
  ROUND(100 * SUM(CASE WHEN has_diabetes = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS diabetes_pct
FROM
  binned_cohort
WHERE
  infarct_type IS NOT NULL
  AND los_bin IS NOT NULL
  AND comorbidity_bin IS NOT NULL
GROUP BY
  infarct_type, los_bin, comorbidity_bin
ORDER BY
  infarct_type, los_bin, comorbidity_bin;