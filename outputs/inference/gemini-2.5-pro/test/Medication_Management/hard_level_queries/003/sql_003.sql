WITH
  -- Step 1: Identify the base cohort of male inpatients aged 39-49
  patient_cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 39 AND 49
  ),
  -- Step 2: Get all unique medications prescribed in the first 24 hours for this cohort
  meds_first_24h AS (
    SELECT DISTINCT
      pr.hadm_id,
      LOWER(pr.drug) AS drug_lower
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    INNER JOIN
      patient_cohort AS pc
      ON pr.hadm_id = pc.hadm_id
    WHERE
      pr.starttime <= DATETIME_ADD(pc.admittime, INTERVAL 24 HOUR)
      AND pr.drug IS NOT NULL
  ),
  -- Step 3: For each patient, count total meds and meds from our interaction lists
  interaction_flags AS (
    SELECT
      hadm_id,
      -- Total unique medications is our "medication complexity" metric
      COUNT(DISTINCT drug_lower) AS med_complexity,
      -- Count distinct QT-prolonging drugs
      COUNT(
        DISTINCT CASE
          WHEN drug_lower LIKE '%amiodarone%'
          OR drug_lower LIKE '%haloperidol%'
          OR drug_lower LIKE '%ondansetron%'
          OR drug_lower LIKE '%ciprofloxacin%'
          OR drug_lower LIKE '%azithromycin%'
          OR drug_lower LIKE '%methadone%'
          OR drug_lower LIKE '%fluconazole%'
          OR drug_lower LIKE '%quetiapine%'
          OR drug_lower LIKE '%levofloxacin%'
          OR drug_lower LIKE '%sotalol%'
          OR drug_lower LIKE '%ziprasidone%'
          THEN drug_lower
        END
      ) AS qt_drug_count,
      -- Count distinct bleeding-risk drugs
      COUNT(
        DISTINCT CASE
          WHEN drug_lower LIKE '%warfarin%'
          OR drug_lower LIKE '%heparin%'
          OR drug_lower LIKE '%enoxaparin%'
          OR drug_lower LIKE '%rivaroxaban%'
          OR drug_lower LIKE '%apixaban%'
          OR drug_lower LIKE '%dabigatran%'
          OR drug_lower LIKE '%aspirin%'
          OR drug_lower LIKE '%clopidogrel%'
          OR drug_lower LIKE '%ticagrelor%'
          OR drug_lower LIKE '%ibuprofen%'
          OR drug_lower LIKE '%naproxen%'
          OR drug_lower LIKE '%ketorolac%'
          THEN drug_lower
        END
      ) AS bleed_drug_count
    FROM
      meds_first_24h
    GROUP BY
      hadm_id
  ),
  -- Step 4 & 5: Combine stats, create flags, and calculate percentile rank
  patient_ranks AS (
    SELECT
      pc.hadm_id,
      pc.los,
      pc.hospital_expire_flag,
      COALESCE(i.med_complexity, 0) AS med_complexity,
      CASE
        WHEN i.qt_drug_count >= 2 THEN 1
        ELSE 0
      END AS is_qt_interaction,
      CASE
        WHEN i.bleed_drug_count >= 2 THEN 1
        ELSE 0
      END AS is_bleeding_interaction,
      PERCENT_RANK() OVER (
        ORDER BY
          COALESCE(i.med_complexity, 0)
      ) AS med_complexity_percentile
    FROM
      patient_cohort AS pc
    LEFT JOIN
      interaction_flags AS i
      ON pc.hadm_id = i.hadm_id
  )
-- Step 6 & 7: Aggregate results into the final report
SELECT
  'General Population' AS cohort_group,
  COUNT(hadm_id) AS number_of_patients,
  AVG(med_complexity) AS avg_medication_complexity,
  AVG(med_complexity_percentile) AS avg_med_complexity_percentile,
  AVG(los) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
FROM
  patient_ranks
UNION ALL
SELECT
  'QT-Prolonging Interaction' AS cohort_group,
  COUNT(hadm_id) AS number_of_patients,
  AVG(med_complexity) AS avg_medication_complexity,
  AVG(med_complexity_percentile) AS avg_med_complexity_percentile,
  AVG(los) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
FROM
  patient_ranks
WHERE
  is_qt_interaction = 1
UNION ALL
SELECT
  'Bleeding-Risk Interaction' AS cohort_group,
  COUNT(hadm_id) AS number_of_patients,
  AVG(med_complexity) AS avg_medication_complexity,
  AVG(med_complexity_percentile) AS avg_med_complexity_percentile,
  AVG(los) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
FROM
  patient_ranks
WHERE
  is_bleeding_interaction = 1
UNION ALL
SELECT
  'Top Quartile (by Med Complexity)' AS cohort_group,
  COUNT(hadm_id) AS number_of_patients,
  NULL AS avg_medication_complexity,
  NULL AS avg_med_complexity_percentile,
  AVG(los) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
FROM
  patient_ranks
WHERE
  med_complexity_percentile >= 0.75
ORDER BY
  number_of_patients DESC;