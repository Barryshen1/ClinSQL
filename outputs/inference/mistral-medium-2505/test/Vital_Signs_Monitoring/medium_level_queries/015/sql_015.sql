WITH
-- Get female patients aged 59-69 with ED admissions and ICU stays
female_ed_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
),

-- Get max SBP per ICU stay (using itemid for SBP, e.g., 220050)
max_sbp_per_stay AS (
  SELECT
    f.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM
    female_ed_patients f
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON f.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    -- Example itemid for SBP (verify in d_items)
    ce.itemid = 220050  -- "Arterial BP [Systolic]"
    AND ce.valuenum IS NOT NULL
  GROUP BY
    f.stay_id
)

-- Calculate 75th percentile of max SBP
SELECT
  PERCENTILE_CONT(max_sbp, 0.75) OVER() AS percentile_75_sbp
FROM
  max_sbp_per_stay
LIMIT 1;