WITH
  -- 1. Charlson Comorbidity Index calculation (Corrected for robustness)
  charlson AS (
    WITH patient_conditions AS (
      SELECT DISTINCT
        hadm_id,
        CASE
          WHEN STARTS_WITH(icd_code, 'I21') OR STARTS_WITH(icd_code, 'I22') OR icd_code = 'I252' THEN 'MI'
          WHEN icd_code IN ('I099', 'I110', 'I130', 'I132', 'I255', 'I420') OR STARTS_WITH(icd_code, 'I425') OR STARTS_WITH(icd_code, 'I426') OR STARTS_WITH(icd_code, 'I427') OR STARTS_WITH(icd_code, 'I428') OR STARTS_WITH(icd_code, 'I429') OR STARTS_WITH(icd_code, 'I43') OR STARTS_WITH(icd_code, 'I50') OR icd_code = 'P290' THEN 'CHF'
          WHEN STARTS_WITH(icd_code, 'I70') OR STARTS_WITH(icd_code, 'I71') OR icd_code IN ('I731', 'I738', 'I739', 'I771', 'I790', 'I792', 'K551', 'K558', 'K559', 'Z958', 'Z959') THEN 'PVD'
          WHEN STARTS_WITH(icd_code, 'G45') OR STARTS_WITH(icd_code, 'G46') OR STARTS_WITH(icd_code, 'I6') OR icd_code = 'H340' THEN 'CeVD'
          WHEN STARTS_WITH(icd_code, 'F00') OR STARTS_WITH(icd_code, 'F01') OR STARTS_WITH(icd_code, 'F02') OR STARTS_WITH(icd_code, 'F03') OR icd_code = 'F051' OR icd_code = 'G30' OR icd_code = 'G311' THEN 'Dementia'
          WHEN STARTS_WITH(icd_code, 'J40') OR STARTS_WITH(icd_code, 'J41') OR STARTS_WITH(icd_code, 'J42') OR STARTS_WITH(icd_code, 'J43') OR STARTS_WITH(icd_code, 'J44') OR STARTS_WITH(icd_code, 'J45') OR STARTS_WITH(icd_code, 'J46') OR STARTS_WITH(icd_code, 'J47') OR STARTS_WITH(icd_code, 'J6') OR icd_code IN ('I278', 'I279', 'J684', 'J701', 'J703') THEN 'CPD'
          WHEN STARTS_WITH(icd_code, 'M05') OR STARTS_WITH(icd_code, 'M06') OR icd_code IN ('M315', 'M351', 'M353', 'M360') OR STARTS_WITH(icd_code, 'M32') OR STARTS_WITH(icd_code, 'M33') OR STARTS_WITH(icd_code, 'M34') THEN 'Rheumatic'
          WHEN STARTS_WITH(icd_code, 'K25') OR STARTS_WITH(icd_code, 'K26') OR STARTS_WITH(icd_code, 'K27') OR STARTS_WITH(icd_code, 'K28') THEN 'PUD'
          WHEN STARTS_WITH(icd_code, 'B18') OR icd_code IN ('K700', 'K701', 'K702', 'K703', 'K709', 'K713', 'K714', 'K715', 'K717', 'K73', 'K74', 'K760', 'K768', 'K769', 'Z944') THEN 'MLD'
          WHEN icd_code IN ('E102', 'E112', 'E122', 'E132', 'E142', 'E103', 'E113', 'E123', 'E133', 'E143', 'E104', 'E114', 'E124', 'E134', 'E144', 'E105', 'E115', 'E125', 'E135', 'E145', 'E107', 'E117', 'E127', 'E137', 'E147') THEN 'DC'
          WHEN icd_code IN ('E100','E101','E106','E108','E109','E110','E111','E116','E118','E119','E120','E121','E126','E128','E129','E130','E131','E136','E138','E139','E140','E141','E146','E148','E149') THEN 'DU'
          WHEN icd_code IN ('G041', 'G114', 'G801', 'G802', 'G81', 'G82', 'G830', 'G831', 'G832', 'G833', 'G834', 'G839') THEN 'Paraplegia'
          WHEN icd_code IN ('I120', 'I131', 'N19', 'N250', 'Z490', 'Z491', 'Z492', 'Z992') OR STARTS_WITH(icd_code, 'N18') OR (STARTS_WITH(icd_code, 'N03') AND SAFE_CAST(SUBSTR(icd_code, 4, 1) AS INT64) BETWEEN 2 AND 7) OR (STARTS_WITH(icd_code, 'N05') AND SAFE_CAST(SUBSTR(icd_code, 4, 1) AS INT64) BETWEEN 2 AND 7) THEN 'Renal'
          WHEN STARTS_WITH(icd_code, 'C') AND NOT (STARTS_WITH(icd_code, 'C77') OR STARTS_WITH(icd_code, 'C78') OR STARTS_WITH(icd_code, 'C79') OR STARTS_WITH(icd_code, 'C80')) THEN 'Malignancy'
          WHEN icd_code IN ('I850', 'I859', 'I864', 'I982', 'K704', 'K711', 'K721', 'K729', 'K765', 'K766') THEN 'SLD'
          WHEN STARTS_WITH(icd_code, 'C77') OR STARTS_WITH(icd_code, 'C78') OR STARTS_WITH(icd_code, 'C79') OR STARTS_WITH(icd_code, 'C80') THEN 'Mets'
          WHEN STARTS_WITH(icd_code, 'B20') OR STARTS_WITH(icd_code, 'B21') OR STARTS_WITH(icd_code, 'B22') OR STARTS_WITH(icd_code, 'B24') THEN 'AIDS'
        END AS charlson_condition
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_version = 10
    )
    SELECT
      hadm_id,
      SUM(
        CASE
          WHEN charlson_condition IN ('MI', 'CHF', 'PVD', 'CeVD', 'Dementia', 'CPD', 'Rheumatic', 'PUD', 'MLD', 'DU') THEN 1
          WHEN charlson_condition IN ('DC', 'Paraplegia', 'Renal', 'Malignancy') THEN 2
          WHEN charlson_condition = 'SLD' THEN 3
          WHEN charlson_condition IN ('Mets', 'AIDS') THEN 6
          ELSE 0
        END
      ) AS charlson_score
    FROM patient_conditions
    WHERE charlson_condition IS NOT NULL
    GROUP BY hadm_id
  ),
  -- 2. Identify hospital admissions with a DVT diagnosis
  dvt_cohort AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      icd_version = 10
      AND (
           STARTS_WITH(icd_code, 'I801') -- Phlebitis/thrombophlebitis of femoral vein
        OR STARTS_WITH(icd_code, 'I802') -- Phlebitis/thrombophlebitis of other deep vessels of lower extremities
        OR icd_code = 'I803'             -- Phlebitis/thrombophlebitis of lower extremities, unspecified
        OR STARTS_WITH(icd_code, 'I824') -- Acute embolism/thrombosis of other deep veins of lower extremity
      )
  ),
  -- 3. Create a base population with all necessary flags and calculated fields
  base_pop AS (
    SELECT
      ad.subject_id,
      ad.hadm_id,
      pa.gender,
      ad.hospital_expire_flag,
      (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year) + pa.anchor_age AS age_at_admission,
      DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
      (pa.dod IS NOT NULL AND pa.dod <= DATETIME_ADD(ad.admittime, INTERVAL 90 DAY)) AS mortality_90day,
      COALESCE(ch.charlson_score, 0) AS charlson_score,
      (dvt.hadm_id IS NOT NULL) AS has_dvt,
      (icu.stay_id IS NOT NULL) AS had_icu_stay
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pa ON ad.subject_id = pa.subject_id
    LEFT JOIN charlson AS ch ON ad.hadm_id = ch.hadm_id
    LEFT JOIN dvt_cohort AS dvt ON ad.hadm_id = dvt.hadm_id
    LEFT JOIN (SELECT hadm_id, MIN(stay_id) AS stay_id FROM `physionet-data.mimiciv_3_1_icu.icustays` GROUP BY hadm_id) AS icu ON ad.hadm_id = icu.hadm_id
  ),
  -- 4. Define the specific study cohort
  study_cohort AS (
    SELECT *
    FROM base_pop
    WHERE
      age_at_admission BETWEEN 71 AND 81
      AND gender = 'M'
      AND has_dvt
      AND charlson_score >= 5 -- "high comorbidity"
  ),
  -- 5. Calculate statistics for the study cohort (Corrected and optimized)
  cohort_stats AS (
    SELECT
      PERCENTILE_CONT(charlson_score, 0.5) AS median_risk_score,
      (PERCENTILE_CONT(charlson_score, 0.75) - PERCENTILE_CONT(charlson_score, 0.25)) AS iqr_risk_score,
      AVG(CAST(mortality_90day AS INT64)) AS mortality_90day_rate,
      AVG(CAST(had_icu_stay AS INT64)) AS complication_rate, -- Using ICU stay as proxy for major complication
      PERCENTILE_CONT(
        IF(hospital_expire_flag = 0, los_days, NULL), 0.5
      ) AS survivor_los_median,
      (PERCENTILE_CONT(
        IF(hospital_expire_flag = 0, los_days, NULL), 0.75
      ) - PERCENTILE_CONT(
        IF(hospital_expire_flag = 0, los_days, NULL), 0.25
      )) AS survivor_los_iqr
    FROM study_cohort
  ),
  -- 6. Calculate statistics for the general inpatient population (Corrected and optimized)
  general_stats AS (
    SELECT
      AVG(CAST(had_icu_stay AS INT64)) AS complication_rate,
      PERCENTILE_CONT(
        IF(hospital_expire_flag = 0, los_days, NULL), 0.5
      ) AS survivor_los_median,
      (PERCENTILE_CONT(
        IF(hospital_expire_flag = 0, los_days, NULL), 0.75
      ) - PERCENTILE_CONT(
        IF(hospital_expire_flag = 0, los_days, NULL), 0.25
      )) AS survivor_los_iqr
    FROM base_pop
    WHERE age_at_admission >= 18
  ),
  -- 7. Calculate percentile for a hypothetical patient with Charlson score of 7
  hypothetical_percentile AS (
    SELECT
      -- Calculate the proportion of patients in the cohort with a score *less than* a hypothetical score of 7
      SAFE_DIVIDE(COUNTIF(charlson_score < 7), COUNT(hadm_id)) AS percentile
    FROM study_cohort
  )
-- Final result assembly
SELECT
  cs.median_risk_score,
  cs.iqr_risk_score,
  cs.mortality_90day_rate,
  cs.complication_rate AS cohort_complication_rate,
  gs.complication_rate AS general_inpatients_complication_rate,
  cs.survivor_los_median AS cohort_survivor_los_median,
  cs.survivor_los_iqr AS cohort_survivor_los_iqr,
  gs.survivor_los_median AS general_inpatients_survivor_los_median,
  gs.survivor_los_iqr AS general_inpatients_survivor_los_iqr,
  hp.percentile AS hypothetical_patient_risk_percentile_cci_7
FROM cohort_stats AS cs, general_stats AS gs, hypothetical_percentile AS hp;