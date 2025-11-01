WITH pneumonia_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_category,
    MAX(CASE WHEN i.intime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS day1_icu,
    MAX(CASE WHEN ce.itemid IN (223848, 223849) THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN ce.itemid IN (221906, 221907, 221908, 221909, 221910) THEN 1 ELSE 0 END) AS vasopressors,
    MAX(CASE WHEN ce.itemid IN (225161, 225162, 225163) THEN 1 ELSE 0 END) AS rrt
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON a.subject_id = ce.subject_id AND a.hadm_id = ce.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' OR d.icd_code LIKE 'J14%'
         OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J17%'
         OR d.icd_code LIKE 'J18%' OR d.icd_code = 'J69.0')
    AND d.icd_code != 'J15.9' -- Exclude unspecified bacterial pneumonia
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, los_days, los_category
)

SELECT
  los_category,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 1) AS mortality_rate,
  SUM(day1_icu) AS day1_icu_count,
  ROUND(SUM(day1_icu) * 100.0 / COUNT(*), 1) AS day1_icu_prevalence,
  SUM(mech_vent) AS mech_vent_count,
  ROUND(SUM(mech_vent) * 100.0 / COUNT(*), 1) AS mech_vent_prevalence,
  SUM(vasopressors) AS vasopressors_count,
  ROUND(SUM(vasopressors) * 100.0 / COUNT(*), 1) AS vasopressors_prevalence,
  SUM(rrt) AS rrt_count,
  ROUND(SUM(rrt) * 100.0 / COUNT(*), 1) AS rrt_prevalence
FROM
  pneumonia_patients
GROUP BY
  los_category
ORDER BY
  los_category;