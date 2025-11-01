WITH
  -- Step 1: Identify admissions for female patients aged 88-98 with an AMI diagnosis.
  ami_admissions AS (
    SELECT DISTINCT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.deathtime,
      p.dod
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON a.hadm_id = dx.hadm_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 88 AND 98
      AND (
        dx.icd_code LIKE '410%' -- ICD-9 for AMI
        OR dx.icd_code LIKE 'I21%' -- ICD-10 for AMI
        OR dx.icd_code LIKE 'I22%' -- ICD-10 for subsequent AMI
      )
  ),

  -- Step 2: For each hospital admission, find the last ICU discharge time. This also filters for admissions that had an ICU stay.
  last_icu_outtime AS (
    SELECT
      hadm_id,
      MAX(outtime) AS last_outtime
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY
      hadm_id
  ),

  -- Step 3: Combine the above to form the final cohort of admissions that meet all criteria (age, gender, AMI, had ICU stay).
  cohort AS (
    SELECT
      ami.subject_id,
      ami.hadm_id,
      ami.admittime,
      ami.deathtime,
      ami.dod,
      icu.last_outtime
    FROM
      ami_admissions AS ami
    INNER JOIN
      last_icu_outtime AS icu ON ami.hadm_id = icu.hadm_id
  ),

  -- Step 4: Identify diagnoses of AKI and ARDS for the cohort admissions.
  complications AS (
    SELECT
      hadm_id,
      MAX(
        CASE
          WHEN
            icd_code LIKE 'N17%' -- ICD-10 for AKI
            OR icd_code LIKE '584%' -- ICD-9 for AKI
            THEN 1
          ELSE 0
        END
      ) AS has_aki,
      MAX(
        CASE
          WHEN
            icd_code = 'J80' -- ICD-10 for ARDS
            OR icd_code = '518.82' -- ICD-9 for ARDS
            THEN 1
          ELSE 0
        END
      ) AS has_ards
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      hadm_id IN (SELECT hadm_id FROM cohort)
    GROUP BY
      hadm_id
  ),

  -- Step 5: Join cohort with complication flags.
  cohort_with_outcomes AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      c.admittime,
      c.deathtime,
      c.dod,
      COALESCE(comp.has_aki, 0) AS has_aki,
      COALESCE(comp.has_ards, 0) AS has_ards
    FROM
      cohort AS c
    LEFT JOIN
      complications AS comp ON c.hadm_id = comp.hadm_id
  )

-- Final Step: Aggregate the results to calculate the final metrics.
SELECT
  COUNT(DISTINCT hadm_id) AS cohort_patient_admissions,
  -- 30-day mortality rate, based on death records vs admission time
  ROUND(
    AVG(
      CASE
        WHEN dod IS NOT NULL AND DATE_DIFF(CAST(dod AS DATE), CAST(admittime AS DATE), DAY) <= 30
          THEN 1.0
        ELSE 0.0
      END
    ) * 100,
    2
  ) AS mortality_rate_30_day_percent,
  -- Rate of AKI diagnosis during the admission
  ROUND(AVG(has_aki) * 100, 2) AS aki_rate_percent,
  -- Rate of ARDS diagnosis during the admission
  ROUND(AVG(has_ards) * 100, 2) AS ards_rate_percent,
  -- Median survival for patients who died in the hospital
  ROUND(
    APPROX_QUANTILES(
      CASE
        WHEN deathtime IS NOT NULL THEN DATETIME_DIFF(deathtime, admittime, HOUR) / 24.0
        ELSE NULL
      END,
      2
    )[OFFSET(1)],
    2
  ) AS median_survival_days_of_decedents
FROM
  cohort_with_outcomes;