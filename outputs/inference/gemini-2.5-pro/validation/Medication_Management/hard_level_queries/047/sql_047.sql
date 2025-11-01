WITH
  -- Step 1: Define the base cohort of female inpatients aged 48-58
  patient_cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 48 AND 58
  ),
  -- Step 2: Identify admissions with a hemorrhagic stroke diagnosis
  hemorrhagic_stroke_hadms AS (
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for hemorrhagic stroke
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432'))
      OR
      -- ICD-10 codes for hemorrhagic stroke
      (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
  ),
  -- Step 3: Label the cohort as 'Hemorrhagic Stroke' or 'Control'
  cohort_with_labels AS (
    SELECT
      pc.*,
      CASE
        WHEN hsh.hadm_id IS NOT NULL
          THEN 'Hemorrhagic Stroke'
        ELSE 'Control'
      END AS cohort_group
    FROM patient_cohort AS pc
    LEFT JOIN hemorrhagic_stroke_hadms AS hsh
      ON pc.hadm_id = hsh.hadm_id
  ),
  -- Step 4: Get prescriptions started in the first 48 hours for the cohort
  meds_first_48h AS (
    SELECT
      c.hadm_id,
      pr.drug
    FROM cohort_with_labels AS c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON c.hadm_id = pr.hadm_id
    WHERE
      pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  ),
  -- Step 5: Calculate medication complexity and count of serotonergic drugs per admission
  medication_stats AS (
    SELECT
      hadm_id,
      COUNT(DISTINCT drug) AS medication_complexity,
      COUNT(DISTINCT CASE
        WHEN
          LOWER(drug) LIKE '%citalopram%' OR LOWER(drug) LIKE '%escitalopram%'
          OR LOWER(drug) LIKE '%fluoxetine%' OR LOWER(drug) LIKE '%fluvoxamine%'
          OR LOWER(drug) LIKE '%paroxetine%' OR LOWER(drug) LIKE '%sertraline%'
          OR LOWER(drug) LIKE '%venlafaxine%' OR LOWER(drug) LIKE '%duloxetine%'
          OR LOWER(drug) LIKE '%desvenlafaxine%' OR LOWER(drug) LIKE '%levomilnacipran%'
          OR LOWER(drug) LIKE '%amitriptyline%' OR LOWER(drug) LIKE '%clomipramine%'
          OR LOWER(drug) LIKE '%doxepin%' OR LOWER(drug) LIKE '%imipramine%'
          OR LOWER(drug) LIKE '%trimipramine%' OR LOWER(drug) LIKE '%desipramine%'
          OR LOWER(drug) LIKE '%nortriptyline%' OR LOWER(drug) LIKE '%phenelzine%'
          OR LOWER(drug) LIKE '%selegiline%' OR LOWER(drug) LIKE '%tranylcypromine%'
          OR LOWER(drug) LIKE '%trazodone%' OR LOWER(drug) LIKE '%mirtazapine%'
          OR LOWER(drug) LIKE '%buspirone%' OR LOWER(drug) LIKE '%tramadol%'
          OR LOWER(drug) LIKE '%fentanyl%' OR LOWER(drug) LIKE '%meperidine%'
          OR LOWER(drug) LIKE '%methadone%' OR LOWER(drug) LIKE '%ondansetron%'
          OR LOWER(drug) LIKE '%granisetron%' OR LOWER(drug) LIKE '%metoclopramide%'
          OR LOWER(drug) LIKE '%linezolid%' OR LOWER(drug) LIKE '%sumatriptan%'
          OR LOWER(drug) LIKE '%zolmitriptan%' OR LOWER(drug) LIKE '%rizatriptan%'
          OR LOWER(drug) LIKE '%eletriptan%'
          THEN drug
      END) AS serotonergic_drug_count
    FROM meds_first_48h
    GROUP BY
      hadm_id
  ),
  -- Step 6: Combine all data, calculate outcomes and create analysis groups
  final_analysis_data AS (
    SELECT
      c.hadm_id,
      c.cohort_group,
      COALESCE(ms.medication_complexity, 0) AS medication_complexity,
      CASE
        WHEN COALESCE(ms.serotonergic_drug_count, 0) >= 2
          THEN '>=2 Serotonergic Drugs'
        ELSE '<2 Serotonergic Drugs'
      END AS serotonergic_group,
      DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS hospital_los,
      c.hospital_expire_flag,
      NTILE(4) OVER (ORDER BY COALESCE(ms.medication_complexity, 0) DESC) AS complexity_quartile
    FROM cohort_with_labels AS c
    LEFT JOIN medication_stats AS ms
      ON c.hadm_id = ms.hadm_id
  ),
  -- Analysis Part 1: Medication complexity distribution
  analysis_part1 AS (
    SELECT
      '1_Medication_Complexity_Distribution' AS analysis,
      cohort_group,
      'Overall' AS subgroup,
      COUNT(hadm_id) AS patient_count,
      AVG(medication_complexity) AS avg_med_complexity,
      STDDEV(medication_complexity) AS stddev_med_complexity,
      MIN(medication_complexity) AS min_med_complexity,
      MAX(medication_complexity) AS max_med_complexity,
      APPROX_QUANTILES(medication_complexity, 4) [OFFSET(1)] AS p25_med_complexity,
      APPROX_QUANTILES(medication_complexity, 4) [OFFSET(2)] AS p50_med_complexity,
      APPROX_QUANTILES(medication_complexity, 4) [OFFSET(3)] AS p75_med_complexity,
      NULL AS avg_los,
      NULL AS mortality_rate
    FROM final_analysis_data
    GROUP BY
      cohort_group
  ),
  -- Analysis Part 2: Outcomes by serotonergic drug use
  analysis_part2 AS (
    SELECT
      '2_Outcomes_by_Serotonergic_Use' AS analysis,
      cohort_group,
      serotonergic_group AS subgroup,
      COUNT(hadm_id) AS patient_count,
      NULL AS avg_med_complexity,
      NULL AS stddev_med_complexity,
      NULL AS min_med_complexity,
      NULL AS max_med_complexity,
      NULL AS p25_med_complexity,
      NULL AS p50_med_complexity,
      NULL AS p75_med_complexity,
      AVG(hospital_los) AS avg_los,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM final_analysis_data
    GROUP BY
      cohort_group,
      serotonergic_group
  ),
  -- Analysis Part 3: Outcomes by top medication complexity quartile
  analysis_part3 AS (
    SELECT
      '3_Outcomes_by_Top_Complexity_Quartile' AS analysis,
      cohort_group,
      CASE
        WHEN complexity_quartile = 1
          THEN 'Top Quartile'
        ELSE 'Bottom 3 Quartiles'
      END AS subgroup,
      COUNT(hadm_id) AS patient_count,
      NULL AS avg_med_complexity,
      NULL AS stddev_med_complexity,
      NULL AS min_med_complexity,
      NULL AS max_med_complexity,
      NULL AS p25_med_complexity,
      NULL AS p50_med_complexity,
      NULL AS p75_med_complexity,
      AVG(hospital_los) AS avg_los,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM final_analysis_data
    GROUP BY
      cohort_group,
      subgroup
  )
-- Final Step: Union all three analysis parts for a comprehensive output
SELECT * FROM analysis_part1
UNION ALL
SELECT * FROM analysis_part2
UNION ALL
SELECT * FROM analysis_part3
ORDER BY
  analysis,
  cohort_group,
  subgroup;