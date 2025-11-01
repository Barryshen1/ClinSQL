WITH sepsis_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.los,
    i.intime,
    i.outtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%shock%'
),

day1_events AS (
  SELECT DISTINCT
    s.stay_id,
    s.hospital_expire_flag,
    s.los,
    CASE WHEN s.los < 8 THEN '<8' ELSE '>=8' END AS los_group,
    MAX(CASE WHEN dp.label IS NOT NULL THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN v.ordercategoryname IS NOT NULL THEN 1 ELSE 0 END) AS vasopressor,
    MAX(CASE WHEN r.ordercategoryname IS NOT NULL THEN 1 ELSE 0 END) AS rrt
  FROM
    sepsis_cohort s
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON s.stay_id = p.stay_id
    AND p.starttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 1 DAY)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` dp
    ON p.itemid = dp.itemid
    AND LOWER(dp.label) LIKE '%mechanical ventilation%'
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` v
    ON s.stay_id = v.stay_id
    AND v.starttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 1 DAY)
    AND LOWER(v.ordercategoryname) LIKE '%vasopressor%'
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` r
    ON s.stay_id = r.stay_id
    AND r.starttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 1 DAY)
    AND LOWER(r.ordercategoryname) LIKE '%dialysis%'
  GROUP BY
    s.stay_id, s.hospital_expire_flag, s.los
)

SELECT
  los_group,
  COUNT(*) AS total_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(mech_vent) * 100 AS mech_vent_pct,
  AVG(vasopressor) * 100 AS vasopressor_pct,
  AVG(rrt) * 100 AS rrt_pct
FROM
  day1_events
GROUP BY
  los_group
ORDER BY
  los_group;