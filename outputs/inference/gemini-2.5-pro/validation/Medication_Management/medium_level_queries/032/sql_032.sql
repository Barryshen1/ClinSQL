WITH
-- Step 1: Define the patient cohort of male patients, aged 51-61,
-- with both Diabetes and Acute Heart Failure diagnoses during their admission.
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN (
    -- Subquery to find admissions with both required diagnoses
    SELECT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
    GROUP BY
      hadm_id
    HAVING
      -- Condition 1: Diabetes diagnosis
      MAX(CASE WHEN LOWER(d.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) = 1
      AND
      -- Condition 2: Acute Heart Failure diagnosis
      MAX(CASE WHEN LOWER(d.long_title) LIKE '%acute%heart failure%' THEN 1 ELSE 0 END) = 1
  ) AS diagnoses_filtered
    ON a.hadm_id = diagnoses_filtered.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.dischtime IS NOT NULL -- Required for the 'final 12h' window calculation
),

-- Step 2: For each patient, determine their insulin regimen in each time window.
patient_regimens AS (
  SELECT
    c.hadm_id,
    -- First 24h regimen classification
    CASE
      WHEN MAX(CASE WHEN ph.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) AND ph.stoptime >= c.admittime AND ph.infusion_type = 'BASAL' THEN 1 ELSE 0 END) = 1
       AND MAX(CASE WHEN ph.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) AND ph.stoptime >= c.admittime AND ph.infusion_type = 'BOLUS' THEN 1 ELSE 0 END) = 1
        THEN 'Basal-Bolus'
      WHEN MAX(CASE WHEN ph.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) AND ph.stoptime >= c.admittime AND ph.infusion_type = 'BASAL' THEN 1 ELSE 0 END) = 1
        THEN 'Basal'
      WHEN MAX(CASE WHEN ph.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) AND ph.stoptime >= c.admittime AND ph.infusion_type = 'BOLUS' THEN 1 ELSE 0 END) = 1
        THEN 'Bolus'
      WHEN MAX(CASE WHEN ph.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) AND ph.stoptime >= c.admittime AND ph.sliding_scale = 'True' THEN 1 ELSE 0 END) = 1
        THEN 'Sliding-Scale'
      ELSE NULL
    END AS regimen_first_24h,
    -- Final 12h regimen classification
    CASE
      WHEN MAX(CASE WHEN ph.starttime <= c.dischtime AND ph.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND ph.infusion_type = 'BASAL' THEN 1 ELSE 0 END) = 1
       AND MAX(CASE WHEN ph.starttime <= c.dischtime AND ph.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND ph.infusion_type = 'BOLUS' THEN 1 ELSE 0 END) = 1
        THEN 'Basal-Bolus'
      WHEN MAX(CASE WHEN ph.starttime <= c.dischtime AND ph.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND ph.infusion_type = 'BASAL' THEN 1 ELSE 0 END) = 1
        THEN 'Basal'
      WHEN MAX(CASE WHEN ph.starttime <= c.dischtime AND ph.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND ph.infusion_type = 'BOLUS' THEN 1 ELSE 0 END) = 1
        THEN 'Bolus'
      WHEN MAX(CASE WHEN ph.starttime <= c.dischtime AND ph.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND ph.sliding_scale = 'True' THEN 1 ELSE 0 END) = 1
        THEN 'Sliding-Scale'
      ELSE NULL
    END AS regimen_final_12h
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` AS ph
    ON c.hadm_id = ph.hadm_id AND LOWER(ph.medication) LIKE '%insulin%'
  GROUP BY
    c.hadm_id, c.admittime, c.dischtime
),

-- Subquery for the total number of patients in the cohort for percentage calculation
total_cohort AS (
  SELECT COUNT(hadm_id) AS total_count FROM cohort
)

-- Step 3: Aggregate results and calculate prevalence and change
SELECT
  reg.regimen,
  -- Calculate prevalence for first 24h
  SAFE_DIVIDE(COUNT(CASE WHEN pr.regimen_first_24h = reg.regimen THEN 1 END) * 100.0, tc.total_count) AS percent_prevalence_first_24h,
  -- Calculate prevalence for final 12h
  SAFE_DIVIDE(COUNT(CASE WHEN pr.regimen_final_12h = reg.regimen THEN 1 END) * 100.0, tc.total_count) AS percent_prevalence_final_12h,
  -- Calculate percentage-point change
  SAFE_DIVIDE(
    (COUNT(CASE WHEN pr.regimen_final_12h = reg.regimen THEN 1 END) -
     COUNT(CASE WHEN pr.regimen_first_24h = reg.regimen THEN 1 END)) * 100.0,
    tc.total_count
  ) AS percentage_point_change
FROM (
  -- Define all possible regimens to ensure they appear in the final output
  SELECT 'Basal-Bolus' AS regimen UNION ALL
  SELECT 'Basal' UNION ALL
  SELECT 'Bolus' UNION ALL
  SELECT 'Sliding-Scale'
) AS reg
CROSS JOIN patient_regimens AS pr
CROSS JOIN total_cohort AS tc
GROUP BY
  reg.regimen,
  tc.total_count
ORDER BY
  -- Custom sort order for the output
  CASE reg.regimen
    WHEN 'Basal-Bolus' THEN 1
    WHEN 'Basal' THEN 2
    WHEN 'Bolus' THEN 3
    WHEN 'Sliding-Scale' THEN 4
  END;