WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    -- step-down / IMC units (case-insensitive, flexible matching)
    AND (
      LOWER(icu.first_careunit) LIKE '%step%'
      OR LOWER(icu.first_careunit) LIKE '%imc%'
      OR LOWER(icu.last_careunit) LIKE '%step%'
      OR LOWER(icu.last_careunit) LIKE '%imc%'
    )
),
map_per_stay_cte AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    AVG(ce.valuenum) AS map_per_stay
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE (
        LOWER(di.label) LIKE '%mean arterial pressure%'
        OR LOWER(di.label) LIKE '%mean arterial%'
        OR LOWER(di.label) LIKE '%map%'
      )
    AND ce.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
)
SELECT
  AVG(mpsc.map_per_stay) AS average_map_per_stay
FROM map_per_stay_cte AS mpsc;