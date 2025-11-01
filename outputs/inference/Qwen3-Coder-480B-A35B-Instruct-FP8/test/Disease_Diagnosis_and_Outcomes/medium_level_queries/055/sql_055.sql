WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS unit_type,
    COALESCE(i.los, DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE LOWER(d.long_title) LIKE '%complication%'
    )
),

-- Compute LOS quartiles
los_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM cohort
),

-- Identify interventions
ventilation_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ventilator%' OR LOWER(label) LIKE '%mechanical%'
),

vasopressor_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN (
    'norepinephrine', 'dopamine', 'epinephrine', 'vasopressin'
  )
),

rrt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%' OR LOWER(label) LIKE '%crrt%' OR LOWER(label) LIKE '%cvvh%'
),

interventions AS (
  SELECT
    lq.hadm_id,
    MAX(CASE WHEN v.itemid IS NOT NULL THEN 1 ELSE 0 END) AS mechanical_ventilation,
    MAX(CASE WHEN vp.itemid IS NOT NULL THEN 1 ELSE 0 END) AS vasopressor,
    MAX(CASE WHEN r.itemid IS NOT NULL THEN 1 ELSE 0 END) AS rrt
  FROM los_quartiles lq
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` iv
    ON lq.hadm_id = iv.hadm_id
  LEFT JOIN ventilation_items v
    ON iv.itemid = v.itemid
  LEFT JOIN vasopressor_items vp
    ON iv.itemid = vp.itemid
  LEFT JOIN rrt_items r
    ON iv.itemid = r.itemid
  GROUP BY lq.hadm_id
),

final_data AS (
  SELECT
    lq.unit_type,
    lq.los_quartile,
    COUNT(*) AS patient_count,
    SUM(lq.hospital_expire_flag) AS deaths,
    AVG(lq.hospital_expire_flag) AS mortality_rate,
    AVG(COALESCE(i.mechanical_ventilation, 0)) AS pct_mechanical_ventilation,
    AVG(COALESCE(i.vasopressor, 0)) AS pct_vasopressors,
    AVG(COALESCE(i.rrt, 0)) AS pct_rrt
  FROM los_quartiles lq
  LEFT JOIN interventions i
    ON lq.hadm_id = i.hadm_id
  GROUP BY lq.unit_type, lq.los_quartile
),

q1_baseline AS (
  SELECT
    unit_type,
    mortality_rate AS q1_mortality
  FROM final_data
  WHERE los_quartile = 1
)

SELECT
  f.unit_type,
  f.los_quartile,
  f.patient_count,
  f.deaths,
  ROUND(f.mortality_rate * 100, 2) AS mortality_pct,
  ROUND((f.mortality_rate - b.q1_mortality) * 100, 2) AS abs_diff_from_q1,
  ROUND(
    CASE
      WHEN b.q1_mortality = 0 THEN NULL
      ELSE (f.mortality_rate / b.q1_mortality - 1) * 100
    END, 2
  ) AS rel_diff_from_q1,
  ROUND(f.pct_mechanical_ventilation * 100, 2) AS pct_mechanical_ventilation,
  ROUND(f.pct_vasopressors * 100, 2) AS pct_vasopressors,
  ROUND(f.pct_rrt * 100, 2) AS pct_rrt
FROM final_data f
JOIN q1_baseline b
  ON f.unit_type = b.unit_type
ORDER BY f.unit_type, f.los_quartile;