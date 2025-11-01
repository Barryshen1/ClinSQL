WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8'
      ELSE '>=8'
    END AS los_bin
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND dd.long_title LIKE '%sepsis%'
    AND dd.long_title NOT LIKE '%septic shock%'
),
icu_flags AS (
  SELECT
    sa.*,
    -- Day-1 ICU flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = sa.hadm_id
        AND icu.intime <= TIMESTAMP_ADD(sa.admittime, INTERVAL 1 DAY)
    ) THEN 1 ELSE 0 END AS icu_day1
  FROM sepsis_admissions sa
),
interventions AS (
  SELECT
    icu.hadm_id,
    icu.los_bin,
    icu.icu_day1,
    icu.hospital_expire_flag,
    -- Mechanical ventilation flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu2
        ON ce.stay_id = icu2.stay_id
      WHERE icu2.hadm_id = icu.hadm_id
        AND ce.itemid IN (720, 223848)  -- example ventilation itemids
    ) THEN 1 ELSE 0 END AS mech_vent_flag,
    -- Vasopressors flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu3
        ON ie.stay_id = icu3.stay_id
      WHERE icu3.hadm_id = icu.hadm_id
        AND ie.ordercomponenttypedescription IN ('Norepinephrine','Epinephrine','Vasopressin')
    ) THEN 1 ELSE 0 END AS vasopressor_flag,
    -- RRT flag
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu4
        ON pe.stay_id = icu4.stay_id
      WHERE icu4.hadm_id = icu.hadm_id
        AND LOWER(pe.ordercategorydescription) LIKE '%dialysis%'
    ) THEN 1 ELSE 0 END AS rrt_flag
  FROM icu_flags icu
)
SELECT
  los_bin,
  icu_day1,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS in_hosp_mortality_pct,
  ROUND(100.0 * SUM(mech_vent_flag) / COUNT(*), 1)       AS vent_pct,
  ROUND(100.0 * SUM(vasopressor_flag) / COUNT(*), 1)     AS vasopressor_pct,
  ROUND(100.0 * SUM(rrt_flag) / COUNT(*), 1)             AS rrt_pct
FROM
  interventions
GROUP BY
  los_bin,
  icu_day1
ORDER BY
  los_bin,
  icu_day1;