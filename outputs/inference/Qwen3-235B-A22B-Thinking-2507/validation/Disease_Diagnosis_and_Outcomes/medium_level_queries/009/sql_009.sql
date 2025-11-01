WITH patient_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
    -- Filter for sepsis without septic shock
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      GROUP BY hadm_id
      HAVING 
        SUM(CASE WHEN icd_code IN (
          'A40.0','A40.1','A40.2','A40.3','A40.8','A40.9',
          'A41.0','A41.1','A41.2','A41.3','A41.4','A41.50','A41.51','A41.52','A41.53','A41.54','A41.59','A41.8','A41.9',
          'R65.20'
        ) THEN 1 ELSE 0 END) > 0
        AND SUM(CASE WHEN icd_code = 'R65.21' THEN 1 ELSE 0 END) = 0
    )
),
icu_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    -- Get first ICU stay per admission
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS stay_order
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patient_cohort pc
    ON i.hadm_id = pc.hadm_id
),
day1_interventions AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.los,
    pc.hospital_expire_flag,
    -- Mechanical ventilation on day 1 (first 24 hours of ICU)
    MAX(CASE 
          WHEN ce.itemid IN (223849, 224688, 224689, 224690) 
            AND (
              (ce.itemid = 223849 AND ce.valuenum = 1) OR
              (ce.itemid IN (224688, 224689) AND ce.value IS NOT NULL AND ce.value != 'None') OR
              (ce.itemid = 224690 AND ce.valuenum > 0)
            ) 
          THEN 1 ELSE 0 
        END) AS mech_vent_day1,
    -- Vasopressors on day 1 (norepinephrine, epinephrine, dopamine, vasopressin, phenylephrine)
    MAX(CASE 
          WHEN ie.itemid IN (221906, 221289, 221662, 222315, 221749) 
            AND ie.amount > 0 
          THEN 1 ELSE 0 
        END) AS vaso_day1,
    -- RRT on day 1
    MAX(CASE 
          WHEN pe.itemid IN (227639, 227640, 227641, 227642, 227643) 
          THEN 1 ELSE 0 
        END) AS rrt_day1
  FROM icu_stays i
  INNER JOIN patient_cohort pc ON i.hadm_id = pc.hadm_id
  -- Mechanical ventilation (chartevents)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.stay_id = ce.stay_id
    AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 1 DAY)
    AND ce.itemid IN (223849, 224688, 224689, 224690)
  -- Vasopressors (inputevents)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON i.stay_id = ie.stay_id
    AND ie.starttime <= DATETIME_ADD(i.intime, INTERVAL 1 DAY)
    AND ie.endtime >= i.intime
    AND ie.itemid IN (221906, 221289, 221662, 222315, 221749)
  -- RRT (procedureevents)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 1 DAY)
    AND pe.itemid IN (227639, 227640, 227641, 227642, 227643)
  WHERE i.stay_order = 1
  GROUP BY i.stay_id, i.hadm_id, i.los, pc.hospital_expire_flag
),
los_groups AS (
  SELECT 
    *,
    CASE WHEN los < 8 THEN '<8' ELSE '>=8' END AS los_group
  FROM day1_interventions
)
SELECT 
  los_group,
  COUNT(*) AS total_patients,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_pct,
  ROUND(100 * AVG(mech_vent_day1), 2) AS mech_vent_pct,
  ROUND(100 * AVG(vaso_day1), 2) AS vaso_pct,
  ROUND(100 * AVG(rrt_day1), 2) AS rrt_pct
FROM los_groups
GROUP BY los_group
ORDER BY los_group;