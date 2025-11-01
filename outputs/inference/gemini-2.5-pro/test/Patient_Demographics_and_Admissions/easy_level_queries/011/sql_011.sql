WITH

-- Step 1: Identify hospital admissions with dual antiplatelet therapy (DAPT)
dapt_admissions AS (
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY
    hadm_id
  HAVING
    -- Check for at least one aspirin prescription
    COUNT(CASE WHEN LOWER(drug) LIKE '%aspirin%' THEN 1 END) > 0
    AND
    -- Check for at least one P2Y12 inhibitor prescription (e.g., Clopidogrel, Ticagrelor, Prasugrel)
    COUNT(
      CASE
        WHEN LOWER(drug) LIKE '%clopidogrel%' OR LOWER(drug) LIKE '%plavix%' THEN 1
        WHEN LOWER(drug) LIKE '%ticagrelor%' OR LOWER(drug) LIKE '%brilinta%' THEN 1
        WHEN LOWER(drug) LIKE '%prasugrel%' OR LOWER(drug) LIKE '%effient%' THEN 1
      END
    ) > 0
),

-- Step 2: Identify the first hospital admission for each patient
first_admissions AS (
  SELECT
    subject_id,
    hadm_id
  FROM (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
  )
  WHERE
    rn = 1
),

-- Step 3: Calculate the total ICU length of stay for each hospital admission
total_icu_los AS (
  SELECT
    hadm_id,
    SUM(los) AS total_los_days
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY
    hadm_id
)

-- Step 4: Assemble the final cohort and calculate the average ICU LOS
SELECT
  AVG(t_los.total_los_days) AS average_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
-- Join to filter for only the first admission of each patient
INNER JOIN
  first_admissions AS fa
  ON pat.subject_id = fa.subject_id
-- Join to filter for admissions where DAPT was given
INNER JOIN
  dapt_admissions AS da
  ON fa.hadm_id = da.hadm_id
-- Join to get the total ICU LOS for the admission (also filters for admissions with an ICU stay)
INNER JOIN
  total_icu_los AS t_los
  ON fa.hadm_id = t_los.hadm_id
WHERE
  -- Filter for male patients aged 76-86
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 76 AND 86;