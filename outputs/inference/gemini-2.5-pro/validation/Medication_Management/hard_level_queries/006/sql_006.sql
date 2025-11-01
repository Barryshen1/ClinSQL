WITH
-- Step 1: Define the cohort of male patients (37-47) with a postoperative hospital admission.
cohort_hadm AS (
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
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    -- Filter for hospital admissions that included a surgical service
    AND a.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.services`
      WHERE
        curr_service IN ('SURG', 'CSURG', 'NSURG', 'TSURG', 'VSURG', 'TRAUM')
    )
),

-- Step 2: Isolate the first ICU stay for each hospital admission in our cohort.
first_icu_stay AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    h.dischtime,
    h.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY h.hadm_id ORDER BY i.intime ASC) AS rn
  FROM cohort_hadm AS h
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON h.hadm_id = i.hadm_id
),
cohort_icu AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    dischtime,
    hospital_expire_flag
  FROM first_icu_stay
  WHERE
    rn = 1
),

-- Step 3: Calculate medication complexity for each ICU stay (unique drugs in first 72h).
med_complexity AS (
  SELECT
    icu.stay_id,
    COUNT(DISTINCT pr.drug) AS medication_count
  FROM cohort_icu AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON icu.hadm_id = pr.hadm_id
  WHERE
    -- Filter prescriptions started within the first 72 hours of the ICU stay
    pr.starttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY
    icu.stay_id
),

-- Step 4: Pre-calculate a 30-day readmission flag for all hospital admissions.
readmission_flag AS (
  SELECT
    hadm_id,
    -- Check if the next admission for the same patient is within 30 days of discharge
    CASE
      WHEN
        DATE_DIFF(
          LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime),
          dischtime,
          DAY
        ) <= 30
        THEN 1
      ELSE 0
    END AS readmitted_30_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Step 5: Combine cohort with medication complexity and all outcome metrics.
final_cohort_metrics AS (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.los,
    icu.hospital_expire_flag,
    -- Use COALESCE to assign 0 to patients with no prescriptions in the time window
    COALESCE(mc.medication_count, 0) AS medication_complexity,
    -- Join the readmission flag; COALESCE handles the last admission for a patient
    COALESCE(rf.readmitted_30_days, 0) AS readmitted_30_days
  FROM cohort_icu AS icu
  LEFT JOIN med_complexity AS mc
    ON icu.stay_id = mc.stay_id
  LEFT JOIN readmission_flag AS rf
    ON icu.hadm_id = rf.hadm_id
),

-- Step 6: Stratify the cohort into quintiles based on medication complexity.
cohort_quintiles AS (
  SELECT
    stay_id,
    los,
    hospital_expire_flag,
    readmitted_30_days,
    medication_complexity,
    NTILE(5) OVER (ORDER BY medication_complexity) AS complexity_quintile
  FROM final_cohort_metrics
)

-- Step 7: Final aggregation to report outcomes per quintile.
SELECT
  complexity_quintile,
  COUNT(stay_id) AS number_of_patients,
  MIN(medication_complexity) AS min_med_count,
  MAX(medication_complexity) AS max_med_count,
  ROUND(AVG(medication_complexity), 2) AS avg_med_count,
  ROUND(AVG(los), 2) AS avg_icu_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_rate_percent,
  ROUND(AVG(readmitted_30_days) * 100, 2) AS readmission_rate_30_days_percent
FROM cohort_quintiles
GROUP BY
  complexity_quintile
ORDER BY
  complexity_quintile;