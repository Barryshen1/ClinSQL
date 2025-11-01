WITH sepsis_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    i.intime,
    i.outtime,
    i.los,
    i.stay_id  -- <-- Added missing stay_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      did.icd_code LIKE 'A41%' 
      OR did.icd_code = 'R65.20'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d2
      INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did2
        ON d2.icd_code = did2.icd_code AND d2.icd_version = did2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND did2.icd_code = 'R65.21'
    )
),
interventions AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.los,
    sc.intime,
    sc.hospital_expire_flag,
    -- Mechanical ventilation: itemid 227
    MAX(CASE WHEN pe.itemid = 227 THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN pe.itemid = 227 AND pe.starttime BETWEEN sc.intime AND TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS mech_vent_day1,
    -- Vasopressors: itemids 222315–222319
    MAX(CASE WHEN ie.itemid IN (222315, 222316, 222317, 222318, 222319) THEN 1 ELSE 0 END) AS vasopressors,
    MAX(CASE WHEN ie.itemid IN (222315, 222316, 222317, 222318, 222319) AND ie.starttime BETWEEN sc.intime AND TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS vasopressors_day1,
    -- RRT: itemids 225807, 225808
    MAX(CASE WHEN pe2.itemid IN (225807, 225808) THEN 1 ELSE 0 END) AS rrt,
    MAX(CASE WHEN pe2.itemid IN (225807, 225808) AND pe2.starttime BETWEEN sc.intime AND TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS rrt_day1
  FROM sepsis_cohort sc
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON sc.subject_id = pe.subject_id AND sc.hadm_id = pe.hadm_id AND sc.stay_id = pe.stay_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.inputevents ie
    ON sc.subject_id = ie.subject_id AND sc.hadm_id = ie.hadm_id AND sc.stay_id = ie.stay_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe2
    ON sc.subject_id = pe2.subject_id AND sc.hadm_id = pe2.hadm_id AND sc.stay_id = pe2.stay_id
  GROUP BY sc.subject_id, sc.hadm_id, sc.los, sc.intime, sc.hospital_expire_flag
)
SELECT
  CASE WHEN los < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(mech_vent) * 100 AS mech_vent_prevalence_pct,
  AVG(mech_vent_day1) * 100 AS mech_vent_day1_pct,
  AVG(vasopressors) * 100 AS vasopressors_prevalence_pct,
  AVG(vasopressors_day1) * 100 AS vasopressors_day1_pct,
  AVG(rrt) * 100 AS rrt_prevalence_pct,
  AVG(rrt_day1) * 100 AS rrt_day1_pct
FROM interventions
GROUP BY los_group
ORDER BY los_group;