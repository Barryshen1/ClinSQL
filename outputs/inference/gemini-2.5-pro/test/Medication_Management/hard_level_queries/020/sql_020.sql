WITH
  -- Step 1: Define the patient cohort of females aged 78-88 at admission
  cohort AS (
    SELECT
      p.subject_id,
      ad.hadm_id,
      ad.admittime,
      ad.dischtime,
      ad.hospital_expire_flag,
      -- Calculate age at the time of admission
      EXTRACT(YEAR FROM ad.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
      ON p.subject_id = ad.subject_id
    WHERE
      p.gender = 'F'
      AND (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year + p.anchor_age) BETWEEN 78 AND 88
  ),

  -- Step 2: Calculate the 7-day medication complexity score for each admission
  medication_scores AS (
    SELECT
      c.hadm_id,
      -- The score is the sum of three components, calculated below.
      -- COALESCE is used to handle admissions with no prescriptions, assigning them a count of 0.
      (
        COALESCE(COUNT(DISTINCT pr.drug), 0)
        + (2 * COALESCE(COUNT(DISTINCT
            -- Identify unique high-risk drugs.
            -- This list is a sample and can be modified.
            CASE
              WHEN LOWER(pr.drug) LIKE '%warfarin%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%heparin%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%insulin%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%digoxin%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%amiodarone%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%fentanyl%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%morphine%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%hydromorphone%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%propofol%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%norepinephrine%' THEN pr.drug
              WHEN LOWER(pr.drug) LIKE '%vasopressin%' THEN pr.drug
              ELSE NULL
            END), 0))
        + COALESCE(COUNT(DISTINCT pr.route), 0)
      ) AS med_complexity_score
    FROM
      cohort AS c
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON c.hadm_id = pr.hadm_id
      -- Filter for prescriptions within the first 7 days of admission
      AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    GROUP BY
      c.hadm_id
  ),

  -- Step 3: Calculate 30-day readmission flag for all hospital admissions
  readmissions AS (
    SELECT
      hadm_id,
      -- Flag is 1 if the next admission for the patient is within 30 days of discharge, otherwise 0
      CASE
        WHEN DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
        ELSE 0
      END AS readmitted_30d_flag
    FROM (
      SELECT
        hadm_id,
        dischtime,
        -- Find the next admission time for the same patient
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
    )
  ),

  -- Step 4: Combine all data and assign tertiles based on the complexity score
  combined_data AS (
    SELECT
      c.hadm_id,
      c.hospital_expire_flag,
      -- Calculate Length of Stay in days
      DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
      COALESCE(r.readmitted_30d_flag, 0) AS readmitted_30d_flag,
      ms.med_complexity_score,
      -- Use NTILE to stratify the cohort into 3 tertiles based on the score
      NTILE(3) OVER (ORDER BY ms.med_complexity_score) AS score_tertile
    FROM
      cohort AS c
    INNER JOIN
      medication_scores AS ms
      ON c.hadm_id = ms.hadm_id
    LEFT JOIN
      readmissions AS r
      ON c.hadm_id = r.hadm_id
  )

-- Step 5: Final aggregation to report metrics for each tertile
SELECT
  score_tertile,
  COUNT(hadm_id) AS number_of_admissions,
  -- Show the range of scores within each tertile
  CONCAT(MIN(med_complexity_score), ' - ', MAX(med_complexity_score)) AS score_range,
  ROUND(AVG(los_days), 1) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(readmitted_30d_flag) * 100, 2) AS readmission_30d_pct
FROM
  combined_data
GROUP BY
  score_tertile
ORDER BY
  score_tertile;