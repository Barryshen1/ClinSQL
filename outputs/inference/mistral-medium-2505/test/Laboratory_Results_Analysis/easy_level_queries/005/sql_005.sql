WITH male_icu_stays AS (
  -- Get male patients with ICU stays
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime AS icu_intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
),

first_sodium AS (
  -- Get first serum sodium measurement per ICU stay
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    le.valuenum AS first_sodium,
    ROW_NUMBER() OVER (PARTITION BY m.stay_id ORDER BY le.charttime) AS rn
  FROM
    male_icu_stays m
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    m.subject_id = le.subject_id
    AND m.hadm_id = le.hadm_id
    AND le.itemid = 50912  -- Serum sodium
    AND le.charttime BETWEEN m.icu_intime AND DATE_ADD(m.icu_intime, INTERVAL 1 DAY)  -- Within first day of ICU
  WHERE
    le.valuenum IS NOT NULL
)

-- Calculate IQR of first serum sodium
SELECT
  PERCENTILE_CONT(first_sodium.first_sodium, 0.25) AS q1,
  PERCENTILE_CONT(first_sodium.first_sodium, 0.5) AS median,
  PERCENTILE_CONT(first_sodium.first_sodium, 0.75) AS q3,
  PERCENTILE_CONT(first_sodium.first_sodium, 0.75) - PERCENTILE_CONT(first_sodium.first_sodium, 0.25) AS iqr
FROM
  first_sodium
WHERE
  rn = 1  -- Only first measurement per ICU stay;