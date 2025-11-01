WITH
-- Get male patients aged 77-87
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 77 AND 87
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    eligible_patients p ON s.subject_id = p.subject_id
),

-- Get first GCS total score after ICU admission
first_gcs AS (
  SELECT
    i.subject_id,
    i.stay_id,
    c.valuenum AS gcs_total,
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY c.charttime) AS rn
  FROM
    icu_stays i
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.subject_id = c.subject_id AND i.stay_id = c.stay_id
  WHERE
    c.itemid = 198  -- GCS total score
    AND c.charttime >= i.intime  -- Recorded after ICU admission
    AND c.valuenum IS NOT NULL  -- Ensure numeric value exists
)

-- Calculate average first GCS total
SELECT
  AVG(gcs_total) AS avg_first_gcs_total
FROM
  first_gcs
WHERE
  rn = 1  -- Only the first GCS score per ICU stay
;