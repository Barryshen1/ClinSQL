WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.los AS icu_los,
    a.hospital_expire_flag,
    CASE
      WHEN COUNT(CASE WHEN diag.seq_num > 1 THEN 1 END) BETWEEN 0 AND 2 THEN 'low'
      WHEN COUNT(CASE WHEN diag.seq_num > 1 THEN 1 END) BETWEEN 3 AND 5 THEN 'medium'
      ELSE 'high'
    END AS comorbidity_level,
    CASE
      WHEN i.los <= 5 THEN '≤5'
      ELSE '>5'
    END AS los_stratum,
    MAX(CASE WHEN LOWER(diag_long.long_title) LIKE '%ischemic%' THEN 'ischemic'
             WHEN LOWER(diag_long.long_title) LIKE '%hemorrhagic%' THEN 'hemorrhagic'
        END) AS stroke_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag_long ON diag.icd_code = diag_long.icd_code AND diag.icd_version = diag_long.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      LOWER(diag_long.long_title) LIKE '%ischemic stroke%'
      OR LOWER(diag_long.long_title) LIKE '%hemorrhagic stroke%'
    )
  GROUP BY
    p.subject_id, a.hadm_id, i.stay_id, i.los, a.hospital_expire_flag
  HAVING
    stroke_type IS NOT NULL
),

mech_vent AS (
  SELECT DISTINCT
    pe.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%mechanical ventilation%'
),

vasopressors AS (
  SELECT DISTINCT
    ie.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE
    LOWER(di.label) IN (
      'norepinephrine', 'dopamine', 'epinephrine', 'phenylephrine', 'vasopressin'
    )
),

rrt AS (
  SELECT DISTINCT
    pe.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%dialysis%' OR LOWER(di.label) LIKE '%rrt%'
)

SELECT
  c.stroke_type,
  c.los_stratum,
  c.comorbidity_level,
  COUNT(*) AS n_stays,
  AVG(c.hospital_expire_flag) * 100 AS mortality_pct,
  APPROX_QUANTILES(c.icu_los, 2)[OFFSET(1)] AS median_los,
  AVG(CASE WHEN mv.stay_id IS NOT NULL THEN 1 ELSE 0 END) * 100 AS pct_mech_vent,
  AVG(CASE WHEN vaso.stay_id IS NOT NULL THEN 1 ELSE 0 END) * 100 AS pct_vasopressors,
  AVG(CASE WHEN rrt.stay_id IS NOT NULL THEN 1 ELSE 0 END) * 100 AS pct_rrt
FROM
  cohort c
LEFT JOIN
  mech_vent mv ON c.stay_id = mv.stay_id
LEFT JOIN
  vasopressors vaso ON c.stay_id = vaso.stay_id
LEFT JOIN
  rrt ON c.stay_id = rrt.stay_id
GROUP BY
  c.stroke_type, c.los_stratum, c.comorbidity_level
ORDER BY
  c.stroke_type, c.los_stratum, c.comorbidity_level;