WITH cohort_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON a.subject_id = icu.subject_id
     AND a.hadm_id    = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    -- Filter for step-down or IMC units (case-insensitive)
    AND UPPER(icu.first_careunit) IN ('STEPDOWN', 'IMC')
),

stay_map AS (
  -- Compute mean MAP per ICU stay
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%mean arterial pressure%'
  GROUP BY
    ce.stay_id
)

-- Final aggregation: average of the stay-level mean MAP across the cohort
SELECT
  AVG(sm.mean_map) AS avg_of_mean_map_per_stay,
  COUNT(1)            AS number_of_stays
FROM
  cohort_stays AS cs
  JOIN stay_map AS sm
    ON cs.stay_id = sm.stay_id;