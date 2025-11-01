WITH
  -- Step 1: Create a base cohort of female patients aged 59-69 AT ADMISSION with a DVT diagnosis.
  dvt_cohort_base AS (
    SELECT DISTINCT -- Merged initial and base cohort steps for simplicity
      p.subject_id,
      a.hadm_id,
      p.dod,
      a.admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON a.hadm_id = dx.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
      ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
      p.gender = 'F'
      -- REFINEMENT: Use age at admission for better clinical accuracy.
      AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 59 AND 69
      AND ddx.long_title LIKE '%Deep vein thrombosis%'
  ),

  -- Step 2: Calculate a comorbidity score for each hospital admission (count of unique diagnoses).
  comorbidity_scores AS (
    SELECT
      hadm_id,
      COUNT(DISTINCT icd_code) AS comorbidity_score
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ),

  -- Step 3: Combine the DVT cohort with their comorbidity scores to create the peer group.
  cohort_with_scores AS (
    SELECT
      dcb.subject_id,
      dcb.hadm_id,
      dcb.admittime,
      dcb.dod,
      cs.comorbidity_score
    FROM
      dvt_cohort_base AS dcb
    INNER JOIN
      comorbidity_scores AS cs
      ON dcb.hadm_id = cs.hadm_id
  ),

  -- Step 4: Calculate the 75th percentile of the comorbidity score for the peer group.
  comorbidity_percentile AS (
    SELECT
      APPROX_QUANTILES(comorbidity_score, 100)[OFFSET(75)] AS p75_score
    FROM cohort_with_scores
  ),

  -- Step 5: Define the final cohort by filtering for patients with scores above the 75th percentile.
  final_cohort AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      c.admittime,
      c.dod,
      c.comorbidity_score
    FROM
      cohort_with_scores AS c
    CROSS JOIN
      comorbidity_percentile AS p
    WHERE
      c.comorbidity_score > p.p75_score
  ),

  -- Step 6: Define and identify major complications (PE, Sepsis, AKI, ARDS) for the final cohort.
  major_complication_codes AS (
    SELECT DISTINCT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
      long_title LIKE '%Pulmonary embolism%'
      OR long_title LIKE '%Sepsis%'
      OR long_title LIKE '%Severe sepsis%'
      OR long_title LIKE '%Acute kidney failure%'
      OR long_title LIKE '%Acute respiratory distress syndrome%'
  ),

  subjects_with_major_complications AS (
    SELECT DISTINCT
      fc.subject_id
    FROM
      final_cohort AS fc
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON fc.hadm_id = dx.hadm_id
    INNER JOIN major_complication_codes AS mcc
        ON dx.icd_code = mcc.icd_code AND dx.icd_version = mcc.icd_version
  ),

  -- Step 7: Calculate all the final requested metrics.
  final_metrics AS (
    SELECT
      (SELECT COUNT(DISTINCT subject_id) FROM final_cohort) AS cohort_size,
      (
        SELECT
          AVG(
            CASE
              WHEN DATE_DIFF(DATE(dod), DATE(admittime), DAY) BETWEEN 0 AND 30
                THEN 1.0
              ELSE 0.0
            END
          ) * 100
        FROM final_cohort
      ) AS thirty_day_mortality_rate,
      -- FIX: Use SAFE_DIVIDE to prevent division by zero if the final cohort is empty.
      SAFE_DIVIDE(
        (SELECT COUNT(DISTINCT subject_id) FROM subjects_with_major_complications),
        (SELECT COUNT(DISTINCT subject_id) FROM final_cohort)
      ) * 100.0 AS major_complication_rate,
      (
        SELECT
          -- REFINEMENT: Use 2-quantiles for median for clarity and convention.
          APPROX_QUANTILES(DATE_DIFF(DATE(dod), DATE(admittime), DAY), 2)[OFFSET(1)]
        FROM final_cohort
        WHERE
          dod IS NOT NULL
      ) AS median_survival_days_for_decedents,
      (SELECT APPROX_QUANTILES(comorbidity_score, 4) FROM final_cohort) AS risk_score_quartiles
  )

-- Final Step: Display the results in a clear format.
SELECT
  cohort_size,
  thirty_day_mortality_rate,
  major_complication_rate,
  median_survival_days_for_decedents,
  risk_score_quartiles[OFFSET(1)] AS risk_score_q1,
  risk_score_quartiles[OFFSET(2)] AS risk_score_median,
  risk_score_quartiles[OFFSET(3)] AS risk_score_q3
FROM final_metrics;