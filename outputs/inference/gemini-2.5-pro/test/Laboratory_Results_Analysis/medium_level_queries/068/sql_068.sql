WITH patient_cohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
),

-- CTE to find the first hs-Troponin T measurement for each patient in the cohort
first_troponin AS (
  SELECT
    ranked_labs.subject_id,
    ranked_labs.valuenum
  FROM (
    SELECT
      le.subject_id,
      le.valuenum,
      -- Rank each patient's troponin tests by charttime to find the first one
      ROW_NUMBER() OVER(PARTITION BY le.subject_id ORDER BY le.charttime ASC) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    -- Filter to include only patients from our target cohort
    INNER JOIN
      patient_cohort AS pc
      ON le.subject_id = pc.subject_id
    WHERE
      -- itemid 51003 corresponds to 'Troponin T, High Sensitivity'
      le.itemid = 51003
      AND le.valuenum IS NOT NULL -- Ensure the value is numeric
  ) AS ranked_labs
  WHERE
    ranked_labs.rn = 1 -- Select only the first measurement
)

-- Final step: Categorize the first troponin value and count patients in each category
SELECT
  CASE
    WHEN ft.valuenum < 0.014 THEN 'Normal'
    WHEN ft.valuenum >= 0.014 AND ft.valuenum < 0.04 THEN 'Borderline'
    WHEN ft.valuenum >= 0.04 THEN 'Myocardial Injury'
    ELSE 'Uncategorized' -- Should not be populated with the current logic
  END AS troponin_category,
  COUNT(ft.subject_id) AS patient_count
FROM
  first_troponin AS ft
GROUP BY
  troponin_category
ORDER BY
  -- Custom sort to ensure logical order of categories in the output
  CASE
    WHEN troponin_category = 'Normal' THEN 1
    WHEN troponin_category = 'Borderline' THEN 2
    WHEN troponin_category = 'Myocardial Injury' THEN 3
    ELSE 4
  END;