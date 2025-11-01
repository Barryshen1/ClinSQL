WITH
  -- Step 1: Create a base cohort of male patients aged 41-51 at admission
  -- Also, pre-calculate the next admission time for 30-day readmission analysis
  cohort_base AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      p.anchor_age,
      p.anchor_year,
      -- Calculate the next admission time for the same patient to check for readmission
      LEAD(a.admittime, 1) OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS next_admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      -- Calculate age at admission and filter
      AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 41 AND 51
  ),

  -- Step 2: Filter the base cohort to admissions with diagnoses for BOTH neutropenia and fever
  cohort_diagnosed AS (
    SELECT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      hadm_id IN (SELECT hadm_id FROM cohort_base)
      -- ICD codes in MIMIC-IV are stored without decimals
      AND (
        (icd_version = 9 AND STARTS_WITH(icd_code, '2880'))  -- Neutropenia
        OR (icd_version = 10 AND STARTS_WITH(icd_code, 'D70')) -- Agranulocytosis/Neutropenia
        OR (icd_version = 9 AND STARTS_WITH(icd_code, '7806'))  -- Fever
        OR (icd_version = 10 AND STARTS_WITH(icd_code, 'R50')) -- Fever
      )
    GROUP BY
      hadm_id
    -- Ensure at least one code for each condition is present
    HAVING
      COUNT(DISTINCT
        CASE
          WHEN (icd_version = 9 AND STARTS_WITH(icd_code, '2880')) OR (icd_version = 10 AND STARTS_WITH(icd_code, 'D70'))
            THEN 'neutropenia'
          WHEN (icd_version = 9 AND STARTS_WITH(icd_code, '7806')) OR (icd_version = 10 AND STARTS_WITH(icd_code, 'R50'))
            THEN 'fever'
        END) = 2
  ),

  -- Step 3: Count unique medications prescribed in the first 48 hours for the final cohort
  med_counts AS (
    SELECT
      pr.hadm_id,
      COUNT(DISTINCT pr.drug) AS medication_count
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    INNER JOIN
      cohort_base AS cb ON pr.hadm_id = cb.hadm_id
    WHERE
      pr.hadm_id IN (SELECT hadm_id FROM cohort_diagnosed)
      -- Filter for prescriptions starting within the first 48 hours of admission
      AND pr.starttime <= TIMESTAMP_ADD(cb.admittime, INTERVAL 48 HOUR)
    GROUP BY
      pr.hadm_id
  ),

  -- Step 4: Combine cohort data with medication counts and calculate outcomes for each admission
  cohort_with_outcomes AS (
    SELECT
      cb.hadm_id,
      -- Use COALESCE to handle patients with no medications in the first 48h
      COALESCE(mc.medication_count, 0) AS medication_count,
      -- Calculate LOS in fractional days
      TIMESTAMP_DIFF(cb.dischtime, cb.admittime, SECOND) / (24.0 * 60 * 60) AS los_days,
      cb.hospital_expire_flag,
      -- Flag for 30-day readmission
      CASE
        WHEN cb.dischtime IS NOT NULL AND cb.next_admittime IS NOT NULL
             AND TIMESTAMP_DIFF(cb.next_admittime, cb.dischtime, DAY) <= 30
          THEN 1
        ELSE 0
      END AS readmitted_30_day_flag
    FROM
      cohort_base AS cb
    INNER JOIN
      cohort_diagnosed AS cd
      ON cb.hadm_id = cd.hadm_id
    LEFT JOIN
      med_counts AS mc
      ON cb.hadm_id = mc.hadm_id
  ),

  -- Step 5: Stratify the cohort into tertiles based on medication count
  cohort_with_tertiles AS (
    SELECT
      hadm_id,
      medication_count,
      los_days,
      hospital_expire_flag,
      readmitted_30_day_flag,
      NTILE(3) OVER (ORDER BY medication_count) AS medication_tertile
    FROM
      cohort_with_outcomes
  )

-- Final Step: Aggregate outcomes by tertile and present the final report
SELECT
  medication_tertile,
  COUNT(hadm_id) AS number_of_patients,
  MIN(medication_count) AS min_med_count_in_tertile,
  MAX(medication_count) AS max_med_count_in_tertile,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  AVG(readmitted_30_day_flag) * 100 AS readmission_30_day_percent
FROM
  cohort_with_tertiles
GROUP BY
  medication_tertile
ORDER BY
  medication_tertile;