WITH sepsis_patients AS (
  -- Get male patients aged 53-63 with sepsis diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS icu_los,
    DATE_DIFF(DATE(i.intime), DATE(a.admittime), DAY) AS day1_icu
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      -- Sepsis ICD-10 codes (excluding septic shock)
      (di.icd_code LIKE 'A41.%' OR di.icd_code LIKE 'R65.2%')
      AND di.icd_code NOT LIKE 'R65.21' -- Exclude septic shock
    )
    -- Only first ICU stay per admission
    AND i.stay_id = (
      SELECT MIN(stay_id)
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE hadm_id = a.hadm_id
    )
),

mechanical_ventilation AS (
  -- Identify patients with mechanical ventilation
  SELECT DISTINCT
    subject_id,
    hadm_id,
    stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE
    itemid IN (
      -- Item IDs for mechanical ventilation procedures
      SELECT itemid
      FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE label LIKE '%ventilation%' OR label LIKE '%ventilator%'
    )
),

vasopressors AS (
  -- Identify patients receiving vasopressors
  SELECT DISTINCT
    subject_id,
    hadm_id,
    stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE
    itemid IN (
      -- Item IDs for vasopressor drugs
      SELECT itemid
      FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE label LIKE '%vasopressor%' OR label LIKE '%norepinephrine%' OR label LIKE '%epinephrine%'
    )
),

rrt AS (
  -- Identify patients receiving renal replacement therapy
  SELECT DISTINCT
    subject_id,
    hadm_id,
    stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE
    itemid IN (
      -- Item IDs for RRT procedures
      SELECT itemid
      FROM `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE label LIKE '%dialysis%' OR label LIKE '%hemofiltration%'
    )
)

-- Final aggregation
SELECT
  CASE WHEN icu_los < 8 THEN 'LOS <8 days' ELSE 'LOS ≥8 days' END AS los_group,
  CASE WHEN day1_icu = 1 THEN 'Day 1 ICU' ELSE 'Not Day 1 ICU' END AS day1_icu_group,
  COUNT(DISTINCT s.subject_id) AS total_patients,
  SUM(s.hospital_expire_flag) AS deaths,
  ROUND(100 * SUM(s.hospital_expire_flag) / COUNT(DISTINCT s.subject_id), 2) AS mortality_rate,
  ROUND(100 * COUNT(DISTINCT mv.subject_id) / COUNT(DISTINCT s.subject_id), 2) AS mv_prevalence,
  ROUND(100 * COUNT(DISTINCT v.subject_id) / COUNT(DISTINCT s.subject_id), 2) AS vasopressor_prevalence,
  ROUND(100 * COUNT(DISTINCT r.subject_id) / COUNT(DISTINCT s.subject_id), 2) AS rrt_prevalence
FROM
  sepsis_patients s
LEFT JOIN
  mechanical_ventilation mv ON s.subject_id = mv.subject_id AND s.hadm_id = mv.hadm_id AND s.stay_id = mv.stay_id
LEFT JOIN
  vasopressors v ON s.subject_id = v.subject_id AND s.hadm_id = v.hadm_id AND s.stay_id = v.stay_id
LEFT JOIN
  rrt r ON s.subject_id = r.subject_id AND s.hadm_id = r.hadm_id AND s.stay_id = r.stay_id
GROUP BY
  los_group, day1_icu_group
ORDER BY
  los_group, day1_icu_group;