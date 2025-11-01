WITH
-- Step 1a: Calculate Charlson Comorbidity Index from scratch
charlson_flags AS (
  SELECT
    hadm_id,
    -- For each comorbidity, create a flag (1 if present, 0 if absent)
    MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('410', '412')) OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') OR SUBSTR(icd_code, 1, 5) = 'I25.2')) THEN 1 ELSE 0 END) AS myocardial_infarction,
    MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428') OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50') THEN 1 ELSE 0 END) AS congestive_heart_failure,
    MAX(CASE WHEN (icd_version = 9 AND (icd_code LIKE '443.9%' OR icd_code LIKE '441%' OR icd_code LIKE '785.4%' OR icd_code LIKE 'V43.4%')) OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^I7[013]|K55\.[189]'))) THEN 1 ELSE 0 END) AS peripheral_vascular_disease,
    MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438') OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^(I6[0-9]|G4[56])'))) THEN 1 ELSE 0 END) AS cerebrovascular_disease,
    MAX(CASE WHEN (icd_version = 9 AND (icd_code LIKE '290%' OR icd_code LIKE '294.1%' OR icd_code LIKE '331.2%')) OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^(F0[0-3]|F05\.1|G30|G31\.1)'))) THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '505' OR icd_code LIKE '506.4%' OR icd_code LIKE '508.1%' OR icd_code LIKE '508.8%')) OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^(J4[0-7]|J6[0-7]|J68\.4|J70\.[13])'))) THEN 1 ELSE 0 END) AS chronic_pulmonary_disease,
    MAX(CASE WHEN (icd_version = 9 AND (icd_code LIKE '710.0%' OR icd_code LIKE '710.1%' OR icd_code LIKE '710.4%' OR icd_code LIKE '714.0%' OR icd_code LIKE '714.1%' OR icd_code LIKE '714.2%' OR icd_code LIKE '714.8%' OR icd_code LIKE '725%')) OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^(M0[56]|M31\.5|M3[2-4]|M35\.[13]|M36\.0)'))) THEN 1 ELSE 0 END) AS rheumatic_disease,
    MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '531' AND '534') OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^K2[5-8]')) THEN 1 ELSE 0 END) AS peptic_ulcer_disease,
    MAX(CASE WHEN (icd_version = 9 AND (icd_code LIKE '571.2%' OR icd_code LIKE '571.4%' OR icd_code LIKE '571.5%' OR icd_code LIKE '571.6%')) OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^(B18|K70\.[039]|K71\.[3-57]|K7[34]|K76\.0|K76\.[2-489])'))) THEN 1 ELSE 0 END) AS mild_liver_disease,
    MAX(CASE WHEN (icd_version = 9 AND (REGEXP_CONTAINS(icd_code, r'^250\.[0-389]'))) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E(10|11|13|14)\.[01689]')) THEN 1 ELSE 0 END) AS diabetes_without_cc,
    MAX(CASE WHEN (icd_version = 9 AND (REGEXP_CONTAINS(icd_code, r'^250\.[4-7]'))) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E(10|11|13|14)\.[2-57]')) THEN 1 ELSE 0 END) AS diabetes_with_cc,
    MAX(CASE WHEN (icd_version = 9 AND (icd_code LIKE '344.1%' OR icd_code LIKE '342%')) OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^(G04\.1|G11\.4|G80\.[12]|G8[1-2]|G83\.[0-49])'))) THEN 1 ELSE 0 END) AS paraplegia_hemiplegia,
    MAX(CASE WHEN (icd_version = 9 AND (REGEXP_CONTAINS(icd_code, r'^(403\.[019]|404\.[019]|582|583\.[0-7]|585|586|V42\.0|V45\.1)'))) OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^(I12\.0|I13\.1|N1[89]|N25\.0|Z49\.[0-2]|Z94\.0|Z99\.2)'))) THEN 1 ELSE 0 END) AS renal_disease,
    MAX(CASE WHEN (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(icd_code, 1, 3) BETWEEN '174' AND '195' OR SUBSTR(icd_code, 1, 3) BETWEEN '200' AND '208' OR icd_code LIKE '238.6%')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^C(?!7[7-9]|80)')) THEN 1 ELSE 0 END) AS malignancy,
    MAX(CASE WHEN (icd_version = 9 AND (icd_code LIKE '572.2%' OR icd_code LIKE '572.4%' OR icd_code LIKE '572.8%')) OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^(I85\.[09]|I86\.4|I98\.2|K70\.4|K71\.1|K72\.[19]|K76\.[5-7])'))) THEN 1 ELSE 0 END) AS severe_liver_disease,
    MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '196' AND '199') OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^C(7[7-9]|80)')) THEN 1 ELSE 0 END) AS metastatic_solid_tumor,
    MAX(CASE WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('042', '043', '044')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^B2[0-24]')) THEN 1 ELSE 0 END) AS aids_hiv
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
charlson_score AS (
  SELECT
    hadm_id,
    (
      myocardial_infarction + congestive_heart_failure + peripheral_vascular_disease + cerebrovascular_disease + dementia + chronic_pulmonary_disease + rheumatic_disease + peptic_ulcer_disease +
      paraplegia_hemiplegia * 2 + renal_disease * 2 + aids_hiv * 6 +
      -- Handle hierarchical conditions
      CASE WHEN severe_liver_disease = 1 THEN 3 WHEN mild_liver_disease = 1 THEN 1 ELSE 0 END +
      CASE WHEN diabetes_with_cc = 1 THEN 2 WHEN diabetes_without_cc = 1 THEN 1 ELSE 0 END +
      CASE WHEN metastatic_solid_tumor = 1 THEN 6 WHEN malignancy = 1 THEN 2 ELSE 0 END
    ) AS charlson_comorbidity_index
  FROM charlson_flags
),

-- Step 1b: Define the cohort of male patients aged 53-63 with a Heart Failure diagnosis
cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    COALESCE(ch.charlson_comorbidity_index, 0) AS charlson_comorbidity_index
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON adm.subject_id = pat.subject_id
  LEFT JOIN
    charlson_score AS ch ON adm.hadm_id = ch.hadm_id
  WHERE
    -- Filter for males aged 53-63 at time of admission
    pat.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 53 AND 63
    -- Filter for admissions with a valid LOS
    AND adm.dischtime > adm.admittime
    -- Filter for admissions with a Heart Failure diagnosis (ICD-9: 428.xx, ICD-10: I50.xx)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      WHERE adm.hadm_id = dx.hadm_id
        AND (
          (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
          OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
        )
    )
),

-- Step 2: Calculate LOS and assign patients to LOS, Charlson, and Discharge buckets
cohort_binned AS (
  SELECT
    hadm_id,
    -- Calculate LOS in days, rounding up any partial day
    CEILING(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS los_days,
    hospital_expire_flag,
    CASE
      WHEN CEILING(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) <= 3 THEN '1-3 days'
      WHEN CEILING(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) <= 7 THEN '4-7 days'
      ELSE '>=8 days'
    END AS los_bucket,
    CASE
      WHEN charlson_comorbidity_index <= 3 THEN '<=3'
      WHEN charlson_comorbidity_index <= 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_bucket,
    CASE
      WHEN discharge_location LIKE 'HOME%' THEN 'Home'
      WHEN discharge_location IN ('REHAB/DISTINCT PART HOSP', 'ACUTE REHAB/IRF') THEN 'Rehab'
      WHEN discharge_location LIKE 'SKILLED NURSING%' OR discharge_location = 'SNF' THEN 'SNF'
      WHEN discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
      ELSE 'Other/Expired'
    END AS discharge_destination
  FROM cohort
),

-- Step 3: Group by buckets and calculate primary metrics
grouped_stats AS (
  SELECT
    los_bucket,
    charlson_bucket,
    COUNT(*) AS num_admissions,
    AVG(los_days) AS avg_los_in_group,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 100.0 ELSE 0.0 END) AS in_hospital_mortality_pct,
    AVG(CASE WHEN discharge_destination = 'Home' THEN 100.0 ELSE 0.0 END) AS pct_disch_home,
    AVG(CASE WHEN discharge_destination = 'Rehab' THEN 100.0 ELSE 0.0 END) AS pct_disch_rehab,
    AVG(CASE WHEN discharge_destination = 'SNF' THEN 100.0 ELSE 0.0 END) AS pct_disch_snf,
    AVG(CASE WHEN discharge_destination = 'Hospice' THEN 100.0 ELSE 0.0 END) AS pct_disch_hospice
  FROM cohort_binned
  GROUP BY
    los_bucket,
    charlson_bucket
)

-- Step 4: Calculate LOS differences using window functions and format the final report
SELECT
  los_bucket,
  charlson_bucket,
  num_admissions,
  -- Mortality and Discharge Percentages
  ROUND(in_hospital_mortality_pct, 1) AS in_hospital_mortality_pct,
  ROUND(pct_disch_home, 1) AS discharge_pct_home,
  ROUND(pct_disch_rehab, 1) AS discharge_pct_rehab,
  ROUND(pct_disch_snf, 1) AS discharge_pct_snf,
  ROUND(pct_disch_hospice, 1) AS discharge_pct_hospice,
  -- Absolute and Relative LOS Differences
  ROUND(
    avg_los_in_group - FIRST_VALUE(avg_los_in_group) OVER (PARTITION BY los_bucket ORDER BY CASE charlson_bucket WHEN '<=3' THEN 1 WHEN '4-5' THEN 2 ELSE 3 END),
    2
  ) AS absolute_los_difference_from_baseline,
  ROUND(
    SAFE_DIVIDE(
      avg_los_in_group - FIRST_VALUE(avg_los_in_group) OVER (PARTITION BY los_bucket ORDER BY CASE charlson_bucket WHEN '<=3' THEN 1 WHEN '4-5' THEN 2 ELSE 3 END),
      FIRST_VALUE(avg_los_in_group) OVER (PARTITION BY los_bucket ORDER BY CASE charlson_bucket WHEN '<=3' THEN 1 WHEN '4-5' THEN 2 ELSE 3 END)
    ) * 100,
    1
  ) AS relative_los_difference_pct_from_baseline
FROM
  grouped_stats
ORDER BY
  -- Custom sort order for logical presentation
  CASE los_bucket
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '>=8 days' THEN 3
  END,
  CASE charlson_bucket
    WHEN '<=3' THEN 1
    WHEN '4-5' THEN 2
    WHEN '>5' THEN 3
  END;