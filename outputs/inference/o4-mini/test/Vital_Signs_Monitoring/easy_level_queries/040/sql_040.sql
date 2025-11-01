WITH map_itemids AS (
  -- Identify the itemids corresponding to Mean Arterial Pressure
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),

first_map_per_stay AS (
  -- For each ICU stay, pick the first MAP measurement
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS first_map
  FROM (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      itemid,
      charttime,
      valuenum,
      ROW_NUMBER() OVER (
        PARTITION BY subject_id, hadm_id, stay_id
        ORDER BY charttime
      ) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    WHERE ce.itemid IN (SELECT itemid FROM map_itemids)
      AND ce.valuenum IS NOT NULL
  ) ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  WHERE ce.rn = 1
)

SELECT
  STDDEV_SAMP(fm.first_map) AS sd_first_map
FROM first_map_per_stay fm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON fm.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 55 AND 65;