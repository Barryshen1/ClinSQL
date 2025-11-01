WITH map_items AS (
  -- 1. Find itemids corresponding to Mean Arterial Pressure
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%mean arterial pressure%'
),

patient_icustays AS (
  -- 2. Restrict to male patients aged 52–62 with ICU stays
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

first_map_per_stay AS (
  -- 3. Join to chartevents, filter to MAP itemids, and pick the first measurement per stay
  SELECT
    pis.subject_id,
    pis.hadm_id,
    pis.stay_id,
    ce.charttime,
    ce.valuenum AS first_map
  FROM
    patient_icustays pis
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON pis.subject_id = ce.subject_id
      AND pis.hadm_id    = ce.hadm_id
      AND pis.stay_id    = ce.stay_id
    INNER JOIN map_items mi
      ON ce.itemid = mi.itemid
  WHERE
    ce.charttime >= pis.intime
    AND ce.valuenum IS NOT NULL
),
ranked_first_map AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    first_map,
    ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime ASC) AS rn
  FROM
    first_map_per_stay
)
-- 4. Compute the IQR over all first-recorded MAP values (one per stay)
SELECT
  quantiles[OFFSET(25)] AS p25_map,
  quantiles[OFFSET(75)] AS p75_map,
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_map
FROM (
  SELECT
    APPROX_QUANTILES(first_map, 100) AS quantiles
  FROM (
    SELECT
      first_map
    FROM
      ranked_first_map
    WHERE
      rn = 1
  )
);