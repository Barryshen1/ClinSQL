WITH resp_rate_items AS (
  -- Get itemids for respiratory rate
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),

male_icu_stays AS (
  -- Get ICU stays for males aged 51-61
  SELECT icu.stay_id, icu.subject_id, icu.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
),

first_resp_rate AS (
  -- For each ICU stay, get the first recorded respiratory rate
  SELECT
    s.stay_id,
    ce.charttime,
    ce.valuenum
  FROM male_icu_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON s.stay_id = ce.stay_id
  JOIN resp_rate_items ri
    ON ce.itemid = ri.itemid
  WHERE ce.valuenum IS NOT NULL
),
first_per_stay AS (
  -- Get only the first respiratory rate per stay
  SELECT
    stay_id,
    valuenum AS first_resp_rate
  FROM (
    SELECT
      stay_id,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime ASC) AS rn
    FROM first_resp_rate
  )
  WHERE rn = 1
)

SELECT
  STDDEV_SAMP(first_resp_rate) AS sd_first_resp_rate
FROM first_per_stay
;