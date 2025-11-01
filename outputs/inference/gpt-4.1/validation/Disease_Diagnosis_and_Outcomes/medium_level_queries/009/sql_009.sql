WITH
-- 1. Get sepsis ICD codes (excluding septic shock)
sepsis_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- Sepsis ICD-9
    (icd_version = 9 AND (
      icd_code LIKE '99591' OR
      icd_code LIKE '99593' OR
      icd_code LIKE '038%' OR
      icd_code LIKE '9993%' OR
      icd_code LIKE '7907%' OR
      icd_code LIKE '78559%' OR
      icd_code LIKE '99592%' OR
      icd_code LIKE '99594%'
    ))
    -- Sepsis ICD-10
    OR (icd_version = 10 AND (
      icd_code LIKE 'A41%' OR
      icd_code LIKE 'R6520'
    ))
),
septic_shock_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- Septic shock ICD-9
    (icd_version = 9 AND icd_code = '78552')
    -- Septic shock ICD-10
    OR (icd_version = 10 AND icd_code = 'R6521')
),

-- 2. Get cohort: men aged 53-63 with sepsis (excluding septic shock), with ICU stay
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN (
    -- Only first ICU stay per admission
    SELECT subject_id, hadm_id, MIN(stay_id) AS stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY subject_id, hadm_id
  ) first_icu
    ON a.subject_id = first_icu.subject_id AND a.hadm_id = first_icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON first_icu.stay_id = i.stay_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN sepsis_icd s
        ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN septic_shock_icd ss
        ON d.icd_code = ss.icd_code AND d.icd_version = ss.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
),

-- 3. Identify exposures in day-1 ICU
-- Mechanical ventilation: ICU procedureevents (itemid), hospital procedures_icd (ICD codes)
vent_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ventilat%' OR LOWER(label) LIKE '%intubat%'
),
vaso_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%norepinephrine%'
    OR LOWER(label) LIKE '%epinephrine%'
    OR LOWER(label) LIKE '%vasopressin%'
    OR LOWER(label) LIKE '%dopamine%'
    OR LOWER(label) LIKE '%phenylephrine%'
),
rrt_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%' OR LOWER(label) LIKE '%crrt%' OR LOWER(label) LIKE '%renal replacement%'
),
vent_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    -- ICD-9: 96.7x (mechanical ventilation), 96.04 (intubation)
    (icd_version = 9 AND (icd_code LIKE '967%' OR icd_code = '9604'))
    -- ICD-10: 5A1935Z, 5A1945Z, 5A1955Z (ventilation)
    OR (icd_version = 10 AND icd_code IN ('5A1935Z','5A1945Z','5A1955Z'))
),
rrt_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    -- ICD-9: 39.95 (hemodialysis), 54.98 (peritoneal dialysis)
    (icd_version = 9 AND (icd_code = '3995' OR icd_code = '5498'))
    -- ICD-10: 5A1D00Z, 5A1D60Z, 5A1D70Z (dialysis)
    OR (icd_version = 10 AND icd_code IN ('5A1D00Z','5A1D60Z','5A1D70Z'))
),

exposures AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.icu_intime,
    c.icu_los,
    c.hospital_expire_flag,

    -- Mechanical ventilation: ICU procedureevents or inputevents in day-1, or hospital procedures_icd
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      JOIN vent_itemids vi ON pe.itemid = vi.itemid
      WHERE pe.stay_id = c.stay_id
        AND pe.starttime >= c.icu_intime
        AND pe.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 1 DAY)
    ) OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      JOIN vent_itemids vi ON ie.itemid = vi.itemid
      WHERE ie.stay_id = c.stay_id
        AND ie.starttime >= c.icu_intime
        AND ie.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 1 DAY)
    ) OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      JOIN vent_icd vi ON pi.icd_code = vi.icd_code AND pi.icd_version = vi.icd_version
      WHERE pi.hadm_id = c.hadm_id
    )
    THEN 1 ELSE 0 END AS mech_vent,

    -- Vasopressors: ICU inputevents in day-1
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      JOIN vaso_itemids vi ON ie.itemid = vi.itemid
      WHERE ie.stay_id = c.stay_id
        AND ie.starttime >= c.icu_intime
        AND ie.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 1 DAY)
    )
    THEN 1 ELSE 0 END AS vasopressor,

    -- RRT: ICU procedureevents/inputevents in day-1, or hospital procedures_icd
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      JOIN rrt_itemids ri ON pe.itemid = ri.itemid
      WHERE pe.stay_id = c.stay_id
        AND pe.starttime >= c.icu_intime
        AND pe.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 1 DAY)
    ) OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      JOIN rrt_itemids ri ON ie.itemid = ri.itemid
      WHERE ie.stay_id = c.stay_id
        AND ie.starttime >= c.icu_intime
        AND ie.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 1 DAY)
    ) OR EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      JOIN rrt_icd ri ON pi.icd_code = ri.icd_code AND pi.icd_version = ri.icd_version
      WHERE pi.hadm_id = c.hadm_id
    )
    THEN 1 ELSE 0 END AS rrt

  FROM cohort c
)

SELECT
  CASE WHEN icu_los < 8 THEN '<8' ELSE '>=8' END AS los_group,
  COUNT(*) AS n_patients,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 1) AS mortality_rate_percent,
  ROUND(SUM(mech_vent) * 100.0 / COUNT(*), 1) AS mech_vent_percent,
  ROUND(SUM(vasopressor) * 100.0 / COUNT(*), 1) AS vasopressor_percent,
  ROUND(SUM(rrt) * 100.0 / COUNT(*), 1) AS rrt_percent
FROM exposures
GROUP BY los_group
ORDER BY los_group;