WITH
  HHS_Admissions AS (
    -- Define the cohort of female patients aged 68-78 with an HHS diagnosis
    SELECT DISTINCT
      a.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
      p.gender = 'F'
      AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 68 AND 78
      AND LOWER(dd.long_title) LIKE '%hyperosmolarity%'
  ),

  Hyperkalemia_Risk_Drugs AS (
    -- Define drug classes that increase risk for hyperkalemia. This list is representative, not exhaustive.
    SELECT
      drug_pattern,
      risk_class
    FROM
      UNNEST([
        STRUCT('%lisinopril%' AS drug_pattern, 'ACEI' AS risk_class),
        ('%enalapril%', 'ACEI'), ('%ramipril%', 'ACEI'), ('%benazepril%', 'ACEI'), ('%captopril%', 'ACEI'),
        ('%losartan%', 'ARB'), ('%valsartan%', 'ARB'), ('%irbesartan%', 'ARB'), ('%olmesartan%', 'ARB'),
        ('%spironolactone%', 'K_Sparing_Diuretic'), ('%amiloride%', 'K_Sparing_Diuretic'), ('%eplerenone%', 'K_Sparing_Diuretic'), ('%triamterene%', 'K_Sparing_Diuretic'),
        ('%ibuprofen%', 'NSAID'), ('%naproxen%', 'NSAID'), ('%ketorolac%', 'NSAID'), ('%diclofenac%', 'NSAID'), ('%celecoxib%', 'NSAID'),
        ('%trimethoprim%', 'Other'), ('%cyclosporine%', 'Other'), ('%tacrolimus%', 'Other')
      ])
  ),

  Meds_72h AS (
    -- Identify all unique medications for each admission within the first 72 hours
    SELECT
      pr.hadm_id,
      pr.drug
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON pr.hadm_id = a.hadm_id
    WHERE
      -- Capture drugs active anytime during the first 72h
      pr.starttime < DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
      AND pr.stoptime > a.admittime
  ),

  Med_Complexity AS (
    -- Calculate medication complexity as the count of unique drugs per admission
    SELECT
      hadm_id,
      COUNT(DISTINCT drug) AS med_count
    FROM
      Meds_72h
    GROUP BY
      hadm_id
  ),

  Risk_Interaction_Counts AS (
    -- Count the number of unique hyperkalemia-risk drug classes per admission
    SELECT
      m.hadm_id,
      COUNT(DISTINCT r.risk_class) AS num_risk_classes
    FROM
      Meds_72h AS m
    INNER JOIN
      Hyperkalemia_Risk_Drugs AS r
      ON LOWER(m.drug) LIKE r.drug_pattern
    GROUP BY
      m.hadm_id
  ),

  Patient_Base AS (
    -- Create a base table with all stats for every patient admission
    SELECT
      a.hadm_id,
      a.hospital_expire_flag,
      DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
      COALESCE(mc.med_count, 0) AS med_count,
      COALESCE(ric.num_risk_classes, 0) AS num_risk_classes,
      CASE
        WHEN hhs.hadm_id IS NOT NULL THEN 1 ELSE 0
      END AS is_hhs_cohort
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    LEFT JOIN
      HHS_Admissions AS hhs
      ON a.hadm_id = hhs.hadm_id
    LEFT JOIN
      Med_Complexity AS mc
      ON a.hadm_id = mc.hadm_id
    LEFT JOIN
      Risk_Interaction_Counts AS ric
      ON a.hadm_id = ric.hadm_id
  ),

  Ranked_Patients AS (
    -- Calculate percentile rank of risk-drug class count, partitioned by cohort
    -- This is necessary to compare ranks within the appropriate group
    SELECT
      hadm_id,
      'HHS_68_78_F' AS cohort,
      num_risk_classes,
      PERCENT_RANK() OVER (ORDER BY num_risk_classes) AS interaction_rank
    FROM
      Patient_Base
    WHERE
      is_hhs_cohort = 1
    UNION ALL
    SELECT
      hadm_id,
      'All_Inpatients' AS cohort,
      num_risk_classes,
      PERCENT_RANK() OVER (ORDER BY num_risk_classes) AS interaction_rank
    FROM
      Patient_Base
  )

-- Final aggregation to compute metrics for each cohort
SELECT
  r.cohort,
  -- 72-hour medication complexity distribution
  APPROX_QUANTILES(p.med_count, 100)[OFFSET(25)] AS medication_count_p25,
  APPROX_QUANTILES(p.med_count, 100)[OFFSET(50)] AS medication_count_median,
  APPROX_QUANTILES(p.med_count, 100)[OFFSET(75)] AS medication_count_p75,

  -- Hyperkalemia-risk drug interactions
  SAFE_DIVIDE(COUNTIF(p.num_risk_classes >= 2), COUNT(DISTINCT p.hadm_id)) * 100 AS percent_with_hyperk_risk_interaction,
  APPROX_QUANTILES(IF(p.num_risk_classes >= 2, r.interaction_rank, NULL), 100)[OFFSET(50)] AS median_percentile_rank_of_at_risk_patients,

  -- Top-quartile LOS and mortality
  APPROX_QUANTILES(p.los_days, 4)[OFFSET(3)] AS los_days_p75_top_quartile,
  AVG(p.hospital_expire_flag) * 100 AS mortality_rate_percent
FROM
  Ranked_Patients AS r
INNER JOIN
  Patient_Base AS p
  ON r.hadm_id = p.hadm_id
GROUP BY
  r.cohort
ORDER BY
  r.cohort;