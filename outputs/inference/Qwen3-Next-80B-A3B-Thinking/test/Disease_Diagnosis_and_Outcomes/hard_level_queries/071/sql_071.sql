WITH amicohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND d.icd_code LIKE 'I21%'
    AND d.icd_version = 10
),

grace_components AS (
  SELECT
    c.subject_id,
    c.anchor_age,
    MAX(ce_hr.value) AS heart_rate,
    MIN(ce_bp.value) AS systolic_bp,
    MAX(le_creat.valuenum) AS creatinine,
    MAX(ce_killip.value) AS killip_class,
    CASE WHEN COUNT(DISTINCT d_ca.icd_code) > 0 THEN 1 ELSE 0 END AS cardiac_arrest,
    CASE WHEN COUNT(DISTINCT d_st.icd_code) > 0 THEN 1 ELSE 0 END AS st_elevation,
    CASE WHEN MAX(le_troponin.valuenum) > 0.04 THEN 1 ELSE 0 END AS elevated_enzymes
  FROM
    amicohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce_hr
    ON c.stay_id = ce_hr.stay_id
    AND ce_hr.itemid = 220045
    AND ce_hr.value IS NOT NULL
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce_bp
    ON c.stay_id = ce_bp.stay_id
    AND ce_bp.itemid = 220050
    AND ce_bp.value IS NOT NULL
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le_creat
    ON c.hadm_id = le_creat.hadm_id
    AND le_creat.itemid = 50912
    AND le_creat.valuenum IS NOT NULL
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce_killip
    ON c.stay_id = ce_killip.stay_id
    AND ce_killip.itemid = 223900
    AND ce_killip.value IS NOT NULL
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ca
    ON c.hadm_id = d_ca.hadm_id
    AND d_ca.icd_code LIKE 'I46%'
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_st
    ON c.hadm_id = d_st.hadm_id
    AND d_st.icd_code = 'I21.0'
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le_troponin
    ON c.hadm_id = le_troponin.hadm_id
    AND le_troponin.itemid = 50902
    AND le_troponin.valuenum IS NOT NULL
  GROUP BY
    c.subject_id, c.anchor_age
),

grace_scores AS (
  SELECT
    gc.subject_id,
    (0.048 * gc.anchor_age +
     0.026 * COALESCE(gc.heart_rate, 0) +
     0.034 * COALESCE(gc.systolic_bp, 0) +
     0.015 * COALESCE(gc.creatinine, 0) +
     0.012 * COALESCE(gc.killip_class, 0) +
     0.006 * gc.cardiac_arrest +
     0.011 * gc.st_elevation +
     0.014 * gc.elevated_enzymes) AS grace_score
  FROM
    grace_components gc
),

mortality_90 AS (
  SELECT
    c.subject_id,
    CASE
      WHEN c.hospital_expire_flag = 1 OR (c.dod IS NOT NULL AND c.dod <= DATE_ADD(c.admittime, INTERVAL 90 DAY))
      THEN 1
      ELSE 0
    END AS died_90_days
  FROM
    amicohort c
),

complications AS (
  SELECT
    c.subject_id,
    CASE WHEN COUNT(DISTINCT d_comp.icd_code) > 0 THEN 1 ELSE 0 END AS has_complication
  FROM
    amicohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_comp
    ON c.hadm_id = d_comp.hadm_id
    AND d_comp.icd_code IN ('I50%', 'I6%', 'I97.1')
  GROUP BY
    c.subject_id
),

los_survivors AS (
  SELECT
    c.subject_id,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los
  FROM
    amicohort c
  WHERE
    c.hospital_expire_flag = 0
),

general_cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

general_grace AS (
  SELECT
    gc.subject_id,
    (0.048 * gc.anchor_age +
     0.026 * COALESCE(gc.heart_rate, 0) +
     0.034 * COALESCE(gc.systolic_bp, 0) +
     0.015 * COALESCE(gc.creatinine, 0) +
     0.012 * COALESCE(gc.killip_class, 0) +
     0.006 * gc.cardiac_arrest +
     0.011 * gc.st_elevation +
     0.014 * gc.elevated_enzymes) AS grace_score
  FROM (
    SELECT
      gc.subject_id,
      gc.anchor_age,
      MAX(ce_hr.value) AS heart_rate,
      MIN(ce_bp.value) AS systolic_bp,
      MAX(le_creat.valuenum) AS creatinine,
      MAX(ce_killip.value) AS killip_class,
      CASE WHEN COUNT(DISTINCT d_ca.icd_code) > 0 THEN 1 ELSE 0 END AS cardiac_arrest,
      CASE WHEN COUNT(DISTINCT d_st.icd_code) > 0 THEN 1 ELSE 0 END AS st_elevation,
      CASE WHEN MAX(le_troponin.valuenum) > 0.04 THEN 1 ELSE 0 END AS elevated_enzymes
    FROM
      general_cohort gc
    LEFT JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` ce_hr
      ON gc.hadm_id = ce_hr.hadm_id
      AND ce_hr.itemid = 220045
      AND ce_hr.value IS NOT NULL
    LEFT JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` ce_bp
      ON gc.hadm_id = ce_bp.hadm_id
      AND ce_bp.itemid = 220050
      AND ce_bp.value IS NOT NULL
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` le_creat
      ON gc.hadm_id = le_creat.hadm_id
      AND le_creat.itemid = 50912
      AND le_creat.valuenum IS NOT NULL
    LEFT JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` ce_killip
      ON gc.hadm_id = ce_killip.hadm_id
      AND ce_killip.itemid = 223900
      AND ce_killip.value IS NOT NULL
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ca
      ON gc.hadm_id = d_ca.hadm_id
      AND d_ca.icd_code LIKE 'I46%'
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_st
      ON gc.hadm_id = d_st.hadm_id
      AND d_st.icd_code = 'I21.0'
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` le_troponin
      ON gc.hadm_id = le_troponin.hadm_id
      AND le_troponin.itemid = 50902
      AND le_troponin.valuenum IS NOT NULL
    GROUP BY
      gc.subject_id, gc.anchor_age
  ) gc
),

general_complications AS (
  SELECT
    c.subject_id,
    CASE WHEN COUNT(DISTINCT d_comp.icd_code) > 0 THEN 1 ELSE 0 END AS has_complication
  FROM
    general_cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_comp
    ON c.hadm_id = d_comp.hadm_id
    AND d_comp.icd_code IN ('I50%', 'I6%', 'I97.1')
  GROUP BY
    c.subject_id
),

general_los_survivors AS (
  SELECT
    c.subject_id,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los
  FROM
    general_cohort c
  WHERE
    c.hospital_expire_flag = 0
)

SELECT
  'AMI Cohort' AS cohort_type,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY grace_score) AS median_grace_score,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY grace_score) AS q1_grace_score,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY grace_score) AS q3_grace_score,
  AVG(died_90_days) AS mortality_90_day_rate,
  AVG(has_complication) AS complication_rate,
  AVG(los) AS survivor_los
FROM
  grace_scores gs
JOIN
  mortality_90 m ON gs.subject_id = m.subject_id
JOIN
  complications c ON gs.subject_id = c.subject_id
LEFT JOIN
  los_survivors l ON gs.subject_id = l.subject_id

UNION ALL

SELECT
  'General Inpatients' AS cohort_type,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY grace_score) AS median_grace_score,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY grace_score) AS q1_grace_score,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY grace_score) AS q3_grace_score,
  AVG(died_90_days) AS mortality_90_day_rate,
  AVG(has_complication) AS complication_rate,
  AVG(los) AS survivor_los
FROM (
  SELECT
    gg.subject_id,
    gg.grace_score,
    CASE
      WHEN gc.hospital_expire_flag = 1 OR (gc.dod IS NOT NULL AND gc.dod <= DATE_ADD(gc.admittime, INTERVAL 90 DAY))
      THEN 1
      ELSE 0
    END AS died_90_days,
    gc_comp.has_complication,
    gl.los
  FROM
    general_grace gg
  JOIN
    general_cohort gc ON gg.subject_id = gc.subject_id
  LEFT JOIN
    general_complications gc_comp ON gg.subject_id = gc_comp.subject_id
  LEFT JOIN
    general_los_survivors gl ON gg.subject_id = gl.subject_id
) sub

UNION ALL

SELECT
  'Risk Percentile' AS cohort_type,
  PERCENT_RANK() OVER (ORDER BY grace_score) AS percentile,
  NULL, NULL, NULL, NULL, NULL
FROM
  grace_scores
ORDER BY
  cohort_type;