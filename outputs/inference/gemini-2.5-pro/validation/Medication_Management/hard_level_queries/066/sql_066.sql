WITH
-- Step 1: Calculate outcomes (LOS, mortality, 30-day readmission) for all admissions.
-- This is done first to correctly identify the next admission for the readmission calculation
-- before filtering down to our specific cohort.
admissions_outcomes AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    -- Find the next admission time for this patient to calculate readmission
    LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Step 2: Identify the specific cohort of male patients aged 43-53 with a transplant diagnosis.
transplant_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.los_days,
    adm.hospital_expire_flag,
    -- Calculate 30-day readmission flag based on the next admission time
    CASE
      WHEN DATETIME_DIFF(adm.next_admittime, adm.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmission_30d
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    admissions_outcomes AS adm
    ON p.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(d_dx.long_title) LIKE '%transplant%'
),

-- Step 3: Calculate the medication complexity score for the cohort,
-- defined as the number of unique medications in the first 7 days of admission.
med_scores AS (
  SELECT
    cohort.hadm_id,
    COUNT(DISTINCT rx.drug) AS medication_complexity_score
  FROM
    transplant_cohort AS cohort
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
    ON cohort.hadm_id = rx.hadm_id
  WHERE
    -- Filter prescriptions to the first 7 days of the hospital admission
    rx.starttime >= cohort.admittime AND rx.starttime <= DATETIME_ADD(cohort.admittime, INTERVAL 7 DAY)
  GROUP BY
    cohort.hadm_id
),

-- Step 4: Combine cohort, outcomes, and scores, then stratify by score quartile.
final_data_with_quartiles AS (
  SELECT
    cohort.hadm_id,
    cohort.los_days,
    cohort.hospital_expire_flag,
    cohort.readmission_30d,
    COALESCE(ms.medication_complexity_score, 0) AS medication_complexity_score,
    -- Assign a quartile based on the medication complexity score
    NTILE(4) OVER (ORDER BY COALESCE(ms.medication_complexity_score, 0)) AS score_quartile
  FROM
    transplant_cohort AS cohort
  LEFT JOIN
    med_scores AS ms
    ON cohort.hadm_id = ms.hadm_id
)

-- Step 5: Final aggregation to report metrics per quartile.
SELECT
  score_quartile,
  COUNT(hadm_id) AS n_patients,
  AVG(medication_complexity_score) AS mean_medication_score,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate_percent,
  AVG(readmission_30d) * 100 AS readmission_30d_rate_percent
FROM
  final_data_with_quartiles
GROUP BY
  score_quartile
ORDER BY
  score_quartile;