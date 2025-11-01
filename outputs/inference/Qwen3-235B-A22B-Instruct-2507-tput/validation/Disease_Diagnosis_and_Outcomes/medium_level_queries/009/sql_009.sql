WITH sepsis_patients AS (
  SELECT DISTINCT i.subject_id, i.hadm_id, i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON i.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE LOWER(d_diag.long_title) LIKE '%sepsis%'
    AND LOWER(d_diag.long_title) NOT LIKE '%septic shock%'
),
cohort AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_icu_adm,
    a.hospital_expire_flag,
    -- Mechanical ventilation on day 1
    MAX(CASE
      WHEN pr.itemid IN (
        SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
        WHERE LOWER(label) LIKE '%ventilator%'
           OR LOWER(label) LIKE '%mech%'
           OR LOWER(category) LIKE '%ventilation%'
      )
      AND pr.starttime >= i.intime
      AND pr.starttime < DATETIME_ADD(i.intime, INTERVAL 1 DAY)
      THEN 1 ELSE 0 END) AS vent_day1,
    -- Vasopressors on day 1
    MAX(CASE
      WHEN inp.itemid IN (
        SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
        WHERE LOWER(label) IN ('vasopressin', 'norepinephrine', 'dopamine', 'epinephrine', 'phenylephrine')
      )
      AND inp.starttime >= i.intime
      AND inp.starttime < DATETIME_ADD(i.intime, INTERVAL 1 DAY)
      THEN 1 ELSE 0 END) AS vaso_day1,
    -- RRT on day 1
    MAX(CASE
      WHEN pr.itemid IN (
        SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
        WHERE LOWER(label) LIKE '%dialysis%'
           OR LOWER(label) LIKE '%crrt%'
           OR LOWER(label) LIKE '%hemodialysis%'
      )
      AND pr.starttime >= i.intime
      AND pr.starttime < DATETIME_ADD(i.intime, INTERVAL 1 DAY)
      THEN 1 ELSE 0 END) AS rrt_day1
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  INNER JOIN sepsis_patients s ON i.stay_id = s.stay_id
  -- Left join procedureevents and inputevents to capture interventions
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pr
    ON i.stay_id = pr.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` inp
    ON i.stay_id = inp.stay_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 53 AND 63
  GROUP BY i.stay_id, i.hadm_id, i.intime, i.los, p.gender, age_at_icu_adm, a.hospital_expire_flag
),
cohort_with_los_group AS (
  SELECT
    *,
    CASE WHEN los < 8 THEN '<8' ELSE '≥8' END AS los_group
  FROM cohort
)
SELECT
  los_group,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(vent_day1) * 100, 2) AS vent_prev_pct,
  ROUND(AVG(vaso_day1) * 100, 2) AS vaso_prev_pct,
  ROUND(AVG(rrt_day1) * 100, 2) AS rrt_prev_pct
FROM cohort_with_los_group
GROUP BY los_group
ORDER BY los_group;