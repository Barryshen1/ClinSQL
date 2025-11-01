WITH hf_icd_codes AS (
  -- ICD-9: 428.x; ICD-10: I50.x
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
     OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
),
hf_admissions AS (
  -- Admissions with HF diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN hf_icd_codes hfc
    ON d.icd_code = hfc.icd_code AND d.icd_version = hfc.icd_version
),
male_38_48_hf AS (
  -- Male, age 38-48, HF admissions
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN hf_admissions hfa ON a.subject_id = hfa.subject_id AND a.hadm_id = hfa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
),
icu_status AS (
  -- ICU status per admission
  SELECT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
comorbidity_count AS (
  -- Comorbidity count per admission (excluding HF codes)
  SELECT d.hadm_id, COUNT(DISTINCT CONCAT(d.icd_code, '-', d.icd_version)) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN hf_icd_codes hfc
    ON d.icd_code = hfc.icd_code AND d.icd_version = hfc.icd_version
  WHERE hfc.icd_code IS NULL
  GROUP BY d.hadm_id
),
charlson_map AS (
  -- Map ICD codes to Charlson categories (simplified, see MIT-LCP for full mapping)
  SELECT icd_code, icd_version,
    CASE
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E10|^E11|^E13|^E14')) THEN 'diabetes'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50')) THEN 'chf'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^585')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N18')) THEN 'renal'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^571')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^K70|^K74')) THEN 'liver'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^410')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I21')) THEN 'mi'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^434|^431')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I63|^I61')) THEN 'cva'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^493')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J45')) THEN 'pulmonary'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^140|^141|^142|^143|^144|^145|^146|^147|^148|^149|^150|^151|^152|^153|^154|^155|^156|^157|^158|^159|^160|^161|^162|^163|^164|^165|^170|^171|^172|^174|^175|^176|^179|^180|^181|^182|^183|^184|^185|^186|^187|^188|^189|^190|^191|^192|^193|^194|^195|^196|^197|^198|^199')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^C')) THEN 'malignancy'
      ELSE NULL
    END AS charlson_cat
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
),
charlson_score AS (
  -- Calculate Charlson index per admission (simplified weights)
  SELECT d.hadm_id,
    SUM(
      CASE charlson_cat
        WHEN 'mi' THEN 1
        WHEN 'chf' THEN 1
        WHEN 'cva' THEN 1
        WHEN 'pulmonary' THEN 1
        WHEN 'diabetes' THEN 1
        WHEN 'renal' THEN 1
        WHEN 'liver' THEN 1
        WHEN 'malignancy' THEN 2
        ELSE 0
      END
    ) AS charlson_index
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN charlson_map cm
    ON d.icd_code = cm.icd_code AND d.icd_version = cm.icd_version
  GROUP BY d.hadm_id
),
main AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.admittime,
    m.dischtime,
    m.hospital_expire_flag,
    IFNULL(i.icu_flag, 0) AS icu_flag,
    SAFE_CAST(TIMESTAMP_DIFF(m.dischtime, m.admittime, DAY) AS INT64) AS los_days,
    cc.comorb_count,
    cs.charlson_index
  FROM male_38_48_hf m
  LEFT JOIN icu_status i ON m.hadm_id = i.hadm_id
  LEFT JOIN comorbidity_count cc ON m.hadm_id = cc.hadm_id
  LEFT JOIN charlson_score cs ON m.hadm_id = cs.hadm_id
  WHERE SAFE_CAST(TIMESTAMP_DIFF(m.dischtime, m.admittime, DAY) AS INT64) IS NOT NULL
    AND cs.charlson_index IS NOT NULL
    AND cc.comorb_count IS NOT NULL
)
SELECT
  CASE WHEN icu_flag = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_status,
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    WHEN los_days >= 8 THEN '>=8'
    ELSE 'Unknown'
  END AS los_group,
  CASE
    WHEN charlson_index <= 3 THEN '<=3'
    WHEN charlson_index BETWEEN 4 AND 5 THEN '4-5'
    WHEN charlson_index > 5 THEN '>5'
    ELSE 'Unknown'
  END AS charlson_group,
  COUNT(*) AS n,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_pct,
  -- 95% CI for proportion (Wilson score interval)
  ROUND(
    100.0 * (
      (
        (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) + 1.96*1.96/2) /
        (COUNT(*) + 1.96*1.96)
      ) +
      1.96 * SQRT(
        (
          (
            (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * (COUNT(*) - SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END))) / COUNT(*)
          ) +
          (1.96*1.96/4)
        ) / (COUNT(*) + 1.96*1.96)
      )
    ), 2
  ) AS mortality_95ci_upper,
  ROUND(
    100.0 * (
      (
        (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) + 1.96*1.96/2) /
        (COUNT(*) + 1.96*1.96)
      ) -
      1.96 * SQRT(
        (
          (
            (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * (COUNT(*) - SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END))) / COUNT(*)
          ) +
          (1.96*1.96/4)
        ) / (COUNT(*) + 1.96*1.96)
      )
    ), 2
  ) AS mortality_95ci_lower,
  ROUND(AVG(comorb_count), 2) AS mean_comorbidity_count
FROM main
WHERE los_days >= 1
GROUP BY icu_status, los_group, charlson_group
ORDER BY icu_status, los_group, charlson_group;