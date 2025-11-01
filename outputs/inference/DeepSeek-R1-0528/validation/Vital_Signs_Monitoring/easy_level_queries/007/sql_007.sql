WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    -- Calculate age at admission: anchor_age + (admission year - anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'  -- Filter for females
),
filtered_admissions AS (
  SELECT
    hadm_id
  FROM
    cohort
  WHERE
    age_at_admission BETWEEN 73 AND 83  -- Age filter
),
resp_events AS (
  SELECT
    ce.hadm_id,
    ce.charttime,
    ce.valuenum AS respiratory_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN
    filtered_admissions fa
    ON ce.hadm_id = fa.hadm_id
  WHERE
    ce.itemid = 220210  -- Respiratory Rate itemid
    AND ce.valuenum IS NOT NULL  -- Ensure numeric value exists
),
first_resp_per_admission AS (
  SELECT
    hadm_id,
    respiratory_rate,
    ROW_NUMBER() OVER (
      PARTITION BY hadm_id
      ORDER BY charttime
    ) AS rn  -- Rank respiratory events by time per admission
  FROM
    resp_events
)
SELECT
  STDDEV(respiratory_rate) AS sd_first_respiratory_rate
FROM
  first_resp_per_admission
WHERE
  rn = 1;  -- Select only the first respiratory rate per admission;