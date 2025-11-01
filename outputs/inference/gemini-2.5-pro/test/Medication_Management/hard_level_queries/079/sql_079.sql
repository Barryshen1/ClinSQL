WITH
  -- Step 1: Identify all hospital admissions (hadm_id) with a hemorrhagic stroke diagnosis.
  hemorrhagic_stroke_adms AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for hemorrhagic stroke
      (
        icd_version = 9
        AND (
          icd_code LIKE '430%' -- Subarachnoid hemorrhage
          OR icd_code LIKE '431%' -- Intracerebral hemorrhage
          OR icd_code LIKE '432%' -- Other and unspecified intracranial hemorrhage
        )
      ) -- ICD-10 codes for hemorrhagic stroke
      OR (
        icd_version = 10
        AND (
          icd_code LIKE 'I60%' -- Subarachnoid hemorrhage
          OR icd_code LIKE 'I61%' -- Intracerebral hemorrhage
          OR icd_code LIKE 'I62%' -- Other nontraumatic intracranial hemorrhage
        )
      )
  ),
  -- Step 2: Define the base cohort: male, 89-99 years old, with a hemorrhagic stroke admission.
  cohort AS (
    SELECT
      p.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON adm.subject_id = p.subject_id
    INNER JOIN
      hemorrhagic_stroke_adms AS hsa
      ON adm.hadm_id = hsa.hadm_id
    WHERE
      p.gender = 'M'
      AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 89 AND 99
  ),
  -- Step 3: Calculate medication complexity (unique drugs in first 7 days) for the cohort.
  medication_complexity AS (
    SELECT
      c.hadm_id,
      COUNT(DISTINCT pr.drug) AS num_unique_drugs
    FROM cohort AS c
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON c.hadm_id = pr.hadm_id
      -- Filter prescriptions to the first 7 days of the hospital stay
      AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    GROUP BY
      c.hadm_id
  ),
  -- Step 4: For readmission calculation, get all admissions for the subjects in our cohort.
  subject_admissions AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      -- Find the admission time of the next hospital stay for the same patient
      LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE
      subject_id IN (SELECT DISTINCT subject_id FROM cohort)
  ),
  -- Step 5: Combine cohort with medication complexity and calculate final outcome metrics.
  cohort_final AS (
    SELECT
      c.hadm_id,
      c.hospital_expire_flag,
      -- Calculate Length of Stay in days
      DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
      mc.num_unique_drugs,
      -- Determine 30-day readmission status
      CASE
        -- Deceased patients cannot be readmitted.
        WHEN c.hospital_expire_flag = 1
        THEN 0
        -- Check if the next admission is within 30 days of the current discharge.
        WHEN sa.next_admittime IS NOT NULL AND sa.next_admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
        THEN 1
        ELSE 0
      END AS readmitted_30_days
    FROM cohort AS c
    INNER JOIN
      medication_complexity AS mc
      ON c.hadm_id = mc.hadm_id
    LEFT JOIN
      subject_admissions AS sa
      ON c.hadm_id = sa.hadm_id
  ),
  -- Step 6: Stratify the final cohort into quintiles based on medication complexity.
  cohort_quintiles AS (
    SELECT
      *,
      NTILE(5) OVER (ORDER BY num_unique_drugs) AS med_complexity_quintile
    FROM cohort_final
  )
-- Final Step: Aggregate the results by quintile and report the requested metrics.
SELECT
  med_complexity_quintile,
  COUNT(hadm_id) AS num_patients,
  MIN(num_unique_drugs) AS min_unique_drugs_in_quintile,
  MAX(num_unique_drugs) AS max_unique_drugs_in_quintile,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS inpatient_mortality_percent,
  ROUND(AVG(readmitted_30_days) * 100, 2) AS readmission_30_day_percent
FROM cohort_quintiles
GROUP BY
  med_complexity_quintile
ORDER BY
  med_complexity_quintile;