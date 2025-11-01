WITH
-- Define age range for 76-year-old (71-81)
patient_selection AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age = 76
    AND anchor_year_group = '71-81'
),

-- Get patients with complications of care (ICD codes E870-E879 or T80-T88)
complications_patients AS (
  SELECT DISTINCT
    d.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    d.subject_id IN (SELECT subject_id FROM patient_selection)
    AND (
      (d.icd_code BETWEEN 'E870' AND 'E879')
      OR (d.icd_code BETWEEN 'T80' AND 'T88')
    )
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.los AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    complications_patients c
  ON
    s.subject_id = c.subject_id
),

-- Get non-ICU admissions for these patients
non_icu_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR)/24 AS non_icu_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    complications_patients c
  ON
    a.subject_id = c.subject_id
  WHERE
    a.hadm_id NOT IN (SELECT hadm_id FROM icu_stays)
),

-- Calculate LOS quartiles for ICU and non-ICU
icu_los_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_los,
    NTILE(4) OVER (ORDER BY icu_los) AS los_quartile
  FROM
    icu_stays
),

non_icu_los_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    non_icu_los,
    NTILE(4) OVER (ORDER BY non_icu_los) AS los_quartile
  FROM
    non_icu_admissions
),

-- Combine ICU and non-ICU data
all_patients AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_los AS los,
    los_quartile,
    TRUE AS is_icu
  FROM
    icu_los_quartiles

  UNION ALL

  SELECT
    subject_id,
    hadm_id,
    NULL AS stay_id,
    non_icu_los AS los,
    los_quartile,
    FALSE AS is_icu
  FROM
    non_icu_los_quartiles
),

-- Calculate in-hospital mortality
mortality AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    all_patients p
  ON
    a.subject_id = p.subject_id
    AND a.hadm_id = p.hadm_id
),

-- Calculate mechanical ventilation, vasopressors, RRT
icu_treatments AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    MAX(CASE WHEN ce.itemid IN (223849) THEN 1 ELSE 0 END) AS has_mechanical_ventilation,
    MAX(CASE WHEN ie.itemid IN (221906, 221907, 221908) THEN 1 ELSE 0 END) AS has_vasopressors,
    MAX(CASE WHEN pe.itemid IN (225161, 225162) THEN 1 ELSE 0 END) AS has_rrt
  FROM
    all_patients p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    p.stay_id = ce.stay_id
    AND ce.itemid IN (223849) -- Mechanical ventilation
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
  ON
    p.stay_id = ie.stay_id
    AND ie.itemid IN (221906, 221907, 221908) -- Vasopressors
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON
    p.stay_id = pe.stay_id
    AND pe.itemid IN (225161, 225162) -- RRT
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id
)

-- Final result
SELECT
  p.is_icu,
  p.los_quartile,
  COUNT(*) AS patient_count,
  SUM(m.hospital_expire_flag) AS deaths,
  ROUND(SUM(m.hospital_expire_flag) / COUNT(*), 4) AS mortality_rate,
  ROUND(AVG(CASE WHEN t.has_mechanical_ventilation = 1 THEN 1 ELSE 0 END), 4) AS mechanical_ventilation_pct,
  ROUND(AVG(CASE WHEN t.has_vasopressors = 1 THEN 1 ELSE 0 END), 4) AS vasopressors_pct,
  ROUND(AVG(CASE WHEN t.has_rrt = 1 THEN 1 ELSE 0 END), 4) AS rrt_pct
FROM
  all_patients p
LEFT JOIN
  mortality m
ON
  p.subject_id = m.subject_id
  AND p.hadm_id = m.hadm_id
LEFT JOIN
  icu_treatments t
ON
  p.subject_id = t.subject_id
  AND p.hadm_id = t.hadm_id
  AND (p.stay_id = t.stay_id OR p.stay_id IS NULL)
GROUP BY
  p.is_icu, p.los_quartile
ORDER BY
  p.is_icu DESC, p.los_quartile;