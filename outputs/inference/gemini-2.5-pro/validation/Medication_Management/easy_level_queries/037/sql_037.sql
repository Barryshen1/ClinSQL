WITH ace_prescription_durations AS (
  SELECT
    -- Calculate the duration of each prescription in days
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    ON pr.subject_id = pa.subject_id
  WHERE
    -- 1. Filter for the patient cohort: 55-year-old females
    pa.gender = 'F'
    AND pa.anchor_age = 55

    -- 2. Filter for ACE Inhibitor medications by name using LOWER() and LIKE
    AND (
      LOWER(pr.drug) LIKE '%lisinopril%'
      OR LOWER(pr.drug) LIKE '%enalapril%'
      OR LOWER(pr.drug) LIKE '%enalaprilat%'
      OR LOWER(pr.drug) LIKE '%ramipril%'
      OR LOWER(pr.drug) LIKE '%captopril%'
      OR LOWER(pr.drug) LIKE '%benazepril%'
      OR LOWER(pr.drug) LIKE '%fosinopril%'
      OR LOWER(pr.drug) LIKE '%moexipril%'
      OR LOWER(pr.drug) LIKE '%perindopril%'
      OR LOWER(pr.drug) LIKE '%quinapril%'
      OR LOWER(pr.drug) LIKE '%trandolapril%'
    )

    -- 3. Ensure the start and stop times are valid for duration calculation
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
)
-- 4. Calculate the 25th percentile of the valid prescription durations
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM
  ace_prescription_durations;