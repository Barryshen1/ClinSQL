WITH
  -- Step 1: Identify all hospital admissions for female patients aged 76-86 with a pneumonia diagnosis.
  pneumonia_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    -- Ensure there is a pneumonia diagnosis for this admission
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON a.hadm_id = dx.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
      p.gender = 'F'
      AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 76 AND 86
      AND LOWER(d_dx.long_title) LIKE '%pneumonia%'
    -- Use GROUP BY to get one row per admission, even if they have multiple pneumonia codes
    GROUP BY
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
  ),

  -- Step 2: Calculate medication complexity score (unique drugs in first 7 days) for each admission.
  medication_counts AS (
    SELECT
      pa.hadm_id,
      pa.subject_id,
      pa.admittime,
      pa.dischtime,
      pa.hospital_expire_flag,
      -- Count distinct drugs prescribed in the first 7 days. Use COALESCE for admissions with no prescriptions.
      COALESCE(COUNT(DISTINCT pr.drug), 0) AS med_complexity_score
    FROM pneumonia_admissions AS pa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON pa.hadm_id = pr.hadm_id
      -- Filter for prescriptions started within the first 7 days of hospital admission
      AND pr.starttime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 7 DAY)
    GROUP BY
      pa.hadm_id,
      pa.subject_id,
      pa.admittime,
      pa.dischtime,
      pa.hospital_expire_flag
  ),

  -- Step 3: Calculate 30-day readmission flag for each admission of the relevant patients.
  readmission_data AS (
    SELECT
      hadm_id,
      -- Flag 1 if the next admission is within 30 days of discharge, 0 otherwise
      CASE
        WHEN DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
        ELSE 0
      END AS readmitted_30_days
    FROM (
      SELECT
        hadm_id,
        dischtime,
        -- Get the admission time of the next hospital stay for the same patient
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions`
      -- Only process admissions for the patients in our cohort to improve performance
      WHERE subject_id IN (SELECT DISTINCT subject_id FROM pneumonia_admissions)
    )
  ),

  -- Step 4: Combine metrics and calculate tertiles.
  admissions_with_tertiles AS (
    SELECT
      mc.hadm_id,
      mc.med_complexity_score,
      DATETIME_DIFF(mc.dischtime, mc.admittime, DAY) AS los_days,
      mc.hospital_expire_flag,
      COALESCE(rd.readmitted_30_days, 0) AS readmitted_30_days, -- COALESCE for last admissions which have no 'next' admission
      -- Divide the cohort into 3 groups based on medication complexity score
      NTILE(3) OVER (ORDER BY mc.med_complexity_score) AS tertile
    FROM medication_counts AS mc
    LEFT JOIN readmission_data AS rd
      ON mc.hadm_id = rd.hadm_id
  )

-- Step 5: Aggregate the results by tertile and calculate the final metrics.
SELECT
  tertile,
  COUNT(hadm_id) AS number_of_admissions,
  MIN(med_complexity_score) AS min_med_complexity,
  ROUND(AVG(med_complexity_score), 2) AS avg_med_complexity,
  MAX(med_complexity_score) AS max_med_complexity,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(readmitted_30_days) * 100, 2) AS readmission_30_day_pct
FROM admissions_with_tertiles
GROUP BY
  tertile
ORDER BY
  tertile;