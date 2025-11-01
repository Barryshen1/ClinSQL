WITH map_items AS (
  -- Identify itemids that correspond to Mean Arterial Pressure (MAP)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial%'
     OR LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(abbreviation) LIKE '%map%'
),

male_middle_age_icustays AS (
  -- ICU stays for male patients aged between 48 and 58 (inclusive)
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),

per_stay_max_map AS (
  -- For each eligible ICU stay, compute the maximum MAP observed during the stay
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    MAX(ce.valuenum) AS max_map
  FROM male_middle_age_icustays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = s.stay_id
    AND ce.subject_id = s.subject_id
    AND ce.hadm_id = s.hadm_id
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  WHERE ce.valuenum IS NOT NULL
    -- exclude implausible values
    AND ce.valuenum > 0
    AND ce.valuenum < 300
    -- ensure measurement occurred during the ICU stay window
    AND ce.charttime BETWEEN s.intime AND s.outtime
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
)

-- Final result: average of per-stay maximum MAPs and number of contributing stays
SELECT
  AVG(max_map) AS avg_of_stay_max_map,
  COUNT(*) AS num_stays_contributing
FROM per_stay_max_map;