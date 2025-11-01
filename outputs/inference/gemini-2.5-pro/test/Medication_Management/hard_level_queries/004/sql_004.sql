WITH
  -- Step 1: Identify the base cohort of female patients aged 48-58 and their admissions
  BaseAdmissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 48 AND 58
  ),

  -- Step 2: Identify admissions with a potential NTI drug and CYP3A4 interactor co-prescription
  InteractionAdmissions AS (
    SELECT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE drug IS NOT NULL
    GROUP BY
      hadm_id
    HAVING
      -- Condition 1: At least one Narrow Therapeutic Index (NTI) drug was prescribed
      COUNT(DISTINCT CASE
        WHEN LOWER(drug) LIKE '%warfarin%'
          OR LOWER(drug) LIKE '%digoxin%'
          OR LOWER(drug) LIKE '%lithium%'
          OR LOWER(drug) LIKE '%phenytoin%'
          OR LOWER(drug) LIKE '%theophylline%'
          OR LOWER(drug) LIKE '%tacrolimus%'
          OR LOWER(drug) LIKE '%cyclosporine%'
          OR LOWER(drug) LIKE '%sirolimus%'
          OR LOWER(drug) LIKE '%levothyroxine%'
          THEN drug
      END) > 0
      AND
      -- Condition 2: At least one CYP3A4 interacting drug was prescribed
      COUNT(DISTINCT CASE
        WHEN LOWER(drug) LIKE '%amiodarone%'
          OR LOWER(drug) LIKE '%diltiazem%'
          OR LOWER(drug) LIKE '%verapamil%'
          OR LOWER(drug) LIKE '%clarithromycin%'
          OR LOWER(drug) LIKE '%erythromycin%'
          OR LOWER(drug) LIKE '%ketoconazole%'
          OR LOWER(drug) LIKE '%itraconazole%'
          OR LOWER(drug) LIKE '%ritonavir%'
          OR LOWER(drug) LIKE '%cimetidine%'
          OR LOWER(drug) LIKE '%carbamazepine%'
          OR LOWER(drug) LIKE '%rifampin%'
          OR LOWER(drug) LIKE '%phenobarbital%'
          OR LOWER(drug) LIKE '%phenytoin%' -- Note: Phenytoin is both NTI and an inducer
          THEN drug
      END) > 0
  ),

  -- Step 3: Identify admissions associated with an acute ischemic stroke diagnosis
  StrokeAdmissions AS (
    SELECT DISTINCT
      dia.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
    JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON dia.icd_code = d.icd_code AND dia.icd_version = d.icd_version
    WHERE
      LOWER(d.long_title) LIKE '%ischemic stroke%' OR LOWER(d.long_title) LIKE '%cerebral infarction%'
  ),

  -- Step 4: Calculate a complexity score for each admission based on the number of unique diagnoses
  ComplexityScore AS (
    SELECT
      hadm_id,
      COUNT(DISTINCT icd_code) AS complexity_score
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ),

  -- Step 5: Combine all information into a single cohort for analysis
  CombinedCohort AS (
    SELECT
      b.hadm_id,
      b.los_days,
      b.hospital_expire_flag,
      COALESCE(c.complexity_score, 0) AS complexity_score,
      CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_interaction_flag,
      CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_stroke_patient_flag,
      -- Calculate complexity percentile rank across the entire base cohort
      PERCENT_RANK() OVER (ORDER BY COALESCE(c.complexity_score, 0)) AS complexity_percentile,
      -- Divide stroke patients into complexity quartiles (1 = highest complexity)
      NTILE(4) OVER (PARTITION BY CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END ORDER BY COALESCE(c.complexity_score, 0) DESC) AS complexity_quartile
    FROM
      BaseAdmissions AS b
    LEFT JOIN
      ComplexityScore AS c ON b.hadm_id = c.hadm_id
    LEFT JOIN
      InteractionAdmissions AS i ON b.hadm_id = i.hadm_id
    LEFT JOIN
      StrokeAdmissions AS s ON b.hadm_id = s.hadm_id
  ),

  -- Step 6: Create the first result set comparing cohorts with and without drug interactions
  InteractionComparison AS (
    SELECT
      CASE
        WHEN has_interaction_flag = 1 THEN 'With CYP3A4-NTI Interaction'
        ELSE 'Without CYP3A4-NTI Interaction'
      END AS cohort_group,
      COUNT(hadm_id) AS number_of_admissions,
      AVG(complexity_score) AS avg_complexity_score,
      AVG(complexity_percentile) AS avg_complexity_percentile,
      AVG(los_days) AS avg_los_days,
      AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
    FROM
      CombinedCohort
    GROUP BY
      has_interaction_flag
  ),

  -- Step 7: Create the second result set for top quartile stroke patients
  TopQuartileStroke AS (
    SELECT
      'Top Quartile Complexity Stroke Patients' AS cohort_group,
      COUNT(hadm_id) AS number_of_admissions,
      AVG(los_days) AS avg_los_days,
      AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
    FROM
      CombinedCohort
    WHERE
      is_stroke_patient_flag = 1
      AND complexity_quartile = 1 -- Filter for the top quartile
  )

-- Final Step: Union the two result sets for a comprehensive report
SELECT
  cohort_group,
  number_of_admissions,
  avg_complexity_score,
  avg_complexity_percentile,
  avg_los_days,
  mortality_rate_percent
FROM
  InteractionComparison

UNION ALL

SELECT
  cohort_group,
  number_of_admissions,
  NULL AS avg_complexity_score, -- Column not applicable to this result set
  NULL AS avg_complexity_percentile, -- Column not applicable to this result set
  avg_los_days,
  mortality_rate_percent
FROM
  TopQuartileStroke;