WITH charlson_comorbidities AS (
  -- This CTE flags diagnoses with a Charlson comorbidity based on Quan et al. mappings
  SELECT
    hadm_id,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('410', '412')
             OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') OR SUBSTR(icd_code, 1, 5) = 'I25.2') THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN icd_version = 9 AND (icd_code LIKE '428%' OR SUBSTR(icd_code, 1, 5) IN ('39891', '40201', '40211', '40291') OR SUBSTR(icd_code, 1, 5) IN ('40401', '40403', '40411', '40413', '40491', '40493') OR SUBSTR(icd_code, 1, 4) IN ('4254', '4255', '4257', '4258', '4259'))
             OR icd_version = 10 AND (icd_code LIKE 'I50%' OR icd_code LIKE 'I43%' OR icd_code IN ('I099', 'I110', 'I130', 'I132', 'I255', 'I420', 'I425', 'I426', 'I427', 'I428', 'I429', 'P290')) THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN icd_version = 9 AND (icd_code LIKE '440%' OR icd_code LIKE '441%' OR icd_code LIKE '443.9%' OR SUBSTR(icd_code, 1, 4) IN ('0930', '4373', '4431', '4432', '4438', '4471', '5571', '5579') OR SUBSTR(icd_code, 1, 4) = 'V434')
             OR icd_version = 10 AND (icd_code LIKE 'I70%' OR icd_code LIKE 'I71%' OR icd_code LIKE 'I73.1%' OR icd_code LIKE 'I73.8%' OR icd_code LIKE 'I73.9%' OR icd_code IN ('I771', 'I790', 'I792', 'K551', 'K558', 'K559', 'Z958', 'Z959')) THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438'
             OR icd_version = 10 AND (icd_code LIKE 'G45%' OR icd_code LIKE 'G46%' OR icd_code LIKE 'I6%' OR icd_code LIKE 'H34.0%') THEN 1 ELSE 0 END) AS stroke,
    MAX(CASE WHEN icd_version = 9 AND (icd_code LIKE '290%' OR icd_code LIKE '294.1%' OR icd_code LIKE '331.2%')
             OR icd_version = 10 AND (icd_code LIKE 'F00%' OR icd_code LIKE 'F01%' OR icd_code LIKE 'F02%' OR icd_code LIKE 'F03%' OR icd_code = 'F051' OR icd_code LIKE 'G30%' OR icd_code LIKE 'G31.1%') THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '505' OR SUBSTR(icd_code, 1, 4) IN ('4168', '4169'))
             OR icd_version = 10 AND (icd_code LIKE 'J40%' OR icd_code LIKE 'J41%' OR icd_code LIKE 'J42%' OR icd_code LIKE 'J43%' OR icd_code LIKE 'J44%' OR icd_code LIKE 'J45%' OR icd_code LIKE 'J46%' OR icd_code LIKE 'J47%' OR icd_code LIKE 'J6%' OR icd_code LIKE 'J7%' OR icd_code IN ('I278', 'I279', 'J841', 'J920', 'J961', 'J982', 'J983')) THEN 1 ELSE 0 END) AS pulmonary,
    MAX(CASE WHEN icd_version = 9 AND (icd_code LIKE '710.0%' OR icd_code LIKE '710.1%' OR icd_code LIKE '710.4%' OR icd_code LIKE '714.0%' OR icd_code LIKE '714.1%' OR icd_code LIKE '714.2%' OR icd_code LIKE '714.8%' OR icd_code LIKE '725%')
             OR icd_version = 10 AND (icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code LIKE 'M32%' OR icd_code LIKE 'M33%' OR icd_code LIKE 'M34%' OR icd_code IN ('M315', 'M351', 'M353', 'M360')) THEN 1 ELSE 0 END) AS rheumatic,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('531', '532', '533', '534')
             OR icd_version = 10 AND (icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%') THEN 1 ELSE 0 END) AS pud,
    MAX(CASE WHEN icd_version = 9 AND (icd_code LIKE '571%' OR SUBSTR(icd_code, 1, 4) IN ('0706', '0709', '5700', '5733', '5734', '5738', '5739') OR SUBSTR(icd_code, 1, 5) IN ('07022', '07023', '07032', '07033', '07044', '07054') OR SUBSTR(icd_code, 1, 4) = 'V427')
             OR icd_version = 10 AND (icd_code LIKE 'B18%' OR icd_code LIKE 'K70.0%' OR icd_code LIKE 'K70.3%' OR icd_code LIKE 'K70.9%' OR icd_code LIKE 'K71.3%' OR icd_code LIKE 'K71.4%' OR icd_code LIKE 'K71.5%' OR icd_code LIKE 'K71.7%' OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' OR icd_code LIKE 'K76.0%' OR icd_code LIKE 'K76.8%' OR icd_code LIKE 'K76.9%' OR icd_code = 'Z944') THEN 1 ELSE 0 END) AS liver_mild,
    MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 4) IN ('4560', '4561', '4562') OR SUBSTR(icd_code, 1, 3) = '572' AND SUBSTR(icd_code, 1, 4) != '5720' AND SUBSTR(icd_code, 1, 4) != '5721')
             OR icd_version = 10 AND (icd_code LIKE 'K70.4%' OR icd_code LIKE 'K71.1%' OR icd_code LIKE 'K72.1%' OR icd_code LIKE 'K72.9%' OR icd_code LIKE 'K76.5%' OR icd_code LIKE 'K76.6%' OR icd_code LIKE 'K76.7%' OR icd_code IN ('I850', 'I859', 'I864', 'I982')) THEN 1 ELSE 0 END) AS liver_severe,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2500', '2501', '2502', '2503')
             OR icd_version = 10 AND (icd_code LIKE 'E10.0%' OR icd_code LIKE 'E10.1%' OR icd_code LIKE 'E10.9%' OR icd_code LIKE 'E11.0%' OR icd_code LIKE 'E11.1%' OR icd_code LIKE 'E11.9%' OR icd_code LIKE 'E12.0%' OR icd_code LIKE 'E12.1%' OR icd_code LIKE 'E12.9%' OR icd_code LIKE 'E13.0%' OR icd_code LIKE 'E13.1%' OR icd_code LIKE 'E13.9%' OR icd_code LIKE 'E14.0%' OR icd_code LIKE 'E14.1%' OR icd_code LIKE 'E14.9%') THEN 1 ELSE 0 END) AS diabetes_no_comp,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('2504', '2505', '2506', '2507', '2508', '2509')
             OR icd_version = 10 AND (icd_code LIKE 'E10.2%' OR icd_code LIKE 'E10.3%' OR icd_code LIKE 'E10.4%' OR icd_code LIKE 'E10.5%' OR icd_code LIKE 'E10.6%' OR icd_code LIKE 'E10.7%' OR icd_code LIKE 'E10.8%' OR icd_code LIKE 'E11.2%' OR icd_code LIKE 'E11.3%' OR icd_code LIKE 'E11.4%' OR icd_code LIKE 'E11.5%' OR icd_code LIKE 'E11.6%' OR icd_code LIKE 'E11.7%' OR icd_code LIKE 'E11.8%' OR icd_code LIKE 'E12.2%' OR icd_code LIKE 'E12.3%' OR icd_code LIKE 'E12.4%' OR icd_code LIKE 'E12.5%' OR icd_code LIKE 'E12.6%' OR icd_code LIKE 'E12.7%' OR icd_code LIKE 'E12.8%' OR icd_code LIKE 'E13.2%' OR icd_code LIKE 'E13.3%' OR icd_code LIKE 'E13.4%' OR icd_code LIKE 'E13.5%' OR icd_code LIKE 'E13.6%' OR icd_code LIKE 'E13.7%' OR icd_code LIKE 'E13.8%' OR icd_code LIKE 'E14.2%' OR icd_code LIKE 'E14.3%' OR icd_code LIKE 'E14.4%' OR icd_code LIKE 'E14.5%' OR icd_code LIKE 'E14.6%' OR icd_code LIKE 'E14.7%' OR icd_code LIKE 'E14.8%') THEN 1 ELSE 0 END) AS diabetes_comp,
    MAX(CASE WHEN icd_version = 9 AND (icd_code LIKE '342%' OR icd_code LIKE '343%' OR SUBSTR(icd_code, 1, 4) IN ('3341', '3440', '3441', '3442', '3443', '3444', '3445', '3446', '3449'))
             OR icd_version = 10 AND (icd_code LIKE 'G81%' OR icd_code LIKE 'G82%' OR icd_code LIKE 'G83.0%' OR icd_code LIKE 'G83.1%' OR icd_code LIKE 'G83.2%' OR icd_code LIKE 'G83.3%' OR icd_code LIKE 'G83.4%' OR icd_code LIKE 'G83.9%' OR icd_code IN ('G041', 'G114', 'G801', 'G802')) THEN 1 ELSE 0 END) AS paraplegia,
    MAX(CASE WHEN icd_version = 9 AND (icd_code LIKE '582%' OR icd_code LIKE '583%' OR icd_code LIKE '585%' OR icd_code LIKE '586%' OR icd_code LIKE 'V420%' OR icd_code LIKE 'V451%' OR icd_code LIKE 'V56%' OR SUBSTR(icd_code, 1, 5) IN ('40301', '40311', '40391', '40402', '40412', '40492'))
             OR icd_version = 10 AND (icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' OR icd_code LIKE 'I120%' OR icd_code LIKE 'I131%' OR icd_code IN ('N032', 'N033', 'N034', 'N035', 'N036', 'N037', 'N052', 'N053', 'N054', 'N055', 'N056', 'N057', 'N250', 'Z490', 'Z491', 'Z492', 'Z940', 'Z992')) THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(icd_code, 1, 4) BETWEEN '1740' AND '1958' OR SUBSTR(icd_code, 1, 3) BETWEEN '200' AND '208' OR icd_code = '2386')
             OR icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C26' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C30' AND 'C34' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C37' AND 'C41' OR icd_code = 'C43' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C45' AND 'C58' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C60' AND 'C76' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C81' AND 'C85' OR icd_code IN ('C88', 'C96', 'C97')) THEN 1 ELSE 0 END) AS malignancy,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('196', '197', '198', '199')
             OR icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('C77', 'C78', 'C79', 'C80') THEN 1 ELSE 0 END) AS mets,
    MAX(CASE WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('042', '043', '044')
             OR icd_version = 10 AND icd_code IN ('B20', 'B21', 'B22', 'B24') THEN 1 ELSE 0 END) AS hiv
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
charlson_score AS (
  -- This CTE calculates the final Charlson score, handling mutually exclusive conditions
  SELECT
    hadm_id,
    (mi * 1) + (chf * 1) + (pvd * 1) + (stroke * 1) + (dementia * 1) + (pulmonary * 1) + (rheumatic * 1) + (pud * 1) + (paraplegia * 2) + (renal * 2) + (hiv * 6) +
    CASE WHEN mets = 1 THEN 6 WHEN malignancy = 1 THEN 2 ELSE 0 END +
    CASE WHEN liver_severe = 1 THEN 3 WHEN liver_mild = 1 THEN 1 ELSE 0 END +
    CASE WHEN diabetes_comp = 1 THEN 2 WHEN diabetes_no_comp = 1 THEN 1 ELSE 0 END AS charlson_score
  FROM charlson_comorbidities
),
hf_admissions AS (
  -- This CTE defines the base cohort: male patients, 38-48 years old, with a heart failure diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  WHERE
    pat.gender = 'M' AND pat.anchor_age BETWEEN 38 AND 48
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code LIKE '428%') OR
        (icd_version = 10 AND icd_code LIKE 'I50%')
    )
),
cohort_with_metrics AS (
  -- This CTE joins all data and creates the stratification categories
  SELECT
    hf.hadm_id,
    hf.hospital_expire_flag,
    COALESCE(cs.charlson_score, 0) AS charlson_score,
    CASE
      WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_category,
    CASE
      WHEN DATETIME_DIFF(hf.dischtime, hf.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATETIME_DIFF(hf.dischtime, hf.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN DATETIME_DIFF(hf.dischtime, hf.admittime, DAY) >= 8 THEN '>=8 days'
      ELSE NULL
    END AS los_category,
    CASE
      WHEN COALESCE(cs.charlson_score, 0) <= 3 THEN '<=3'
      WHEN COALESCE(cs.charlson_score, 0) BETWEEN 4 AND 5 THEN '4-5'
      WHEN COALESCE(cs.charlson_score, 0) > 5 THEN '>5'
      ELSE NULL
    END AS charlson_category
  FROM hf_admissions hf
  LEFT JOIN charlson_score cs
    ON hf.hadm_id = cs.hadm_id
  LEFT JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS icu
    ON hf.hadm_id = icu.hadm_id
  WHERE
    hf.admittime IS NOT NULL AND hf.dischtime IS NOT NULL
)
-- Final aggregation and output
SELECT
  icu_category,
  los_category,
  charlson_category,
  COUNT(*) AS total_admissions,
  AVG(charlson_score) AS mean_charlson_score,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS in_hospital_mortality_percent,
  GREATEST(0, (SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) - 1.96 * SQRT(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * (1 - SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))) / COUNT(*)))) * 100 AS mortality_ci95_lower,
  LEAST(100, (SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) + 1.96 * SQRT(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * (1 - SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*))) / COUNT(*)))) * 100 AS mortality_ci95_upper
FROM cohort_with_metrics
WHERE
  los_category IS NOT NULL AND charlson_category IS NOT NULL
GROUP BY
  icu_category,
  los_category,
  charlson_category
ORDER BY
  icu_category,
  CASE los_category
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '>=8 days' THEN 3
  END,
  CASE charlson_category
    WHEN '<=3' THEN 1
    WHEN '4-5' THEN 2
    WHEN '>5' THEN 3
  END;