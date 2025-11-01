WITH sepsis_admissions AS (
  SELECT 
    di.hadm_id,
    MAX(CASE 
        WHEN (di.icd_version = 9 AND (di.icd_code LIKE '038%' OR di.icd_code IN ('99591', '99592'))) 
             OR (di.icd_version = 10 AND (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%' OR di.icd_code = 'R6520'))
        THEN 1 ELSE 0 
    END) AS has_sepsis,
    MAX(CASE 
        WHEN (di.icd_version = 9 AND di.icd_code = '78552') 
             OR (di.icd_version = 10 AND di.icd_code IN ('R6521', 'T8112'))
        THEN 1 ELSE 0 
    END) AS has_shock
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
  HAVING has_sepsis = 1 AND has_shock = 0
),

cohort_admissions AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN sepsis_admissions s
    ON a.hadm_id = s.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
),

icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN cohort_admissions c
    ON i.hadm_id = c.hadm_id
  WHERE 
    i.intime <= DATETIME_ADD(c.admittime, INTERVAL 1 DAY)
),

cohort_icu AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los,
    c.hospital_expire_flag AS mortality,
    -- Mechanical ventilation flag
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
      WHERE p.stay_id = i.stay_id
        AND p.itemid IN (225468, 227194)
        AND p.starttime >= i.intime AND p.starttime <= i.outtime
    ) THEN 1 ELSE 0 END AS mech_vent,
    -- Vasopressors flag
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.ingredientevents` v
      WHERE v.stay_id = i.stay_id
        AND v.itemid IN (221906, 221289, 221662, 222315, 222318)
        AND v.starttime >= i.intime AND v.starttime <= i.outtime
    ) THEN 1 ELSE 0 END AS vasopressor,
    -- RRT flag
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` r
      WHERE r.stay_id = i.stay_id
        AND r.itemid IN (225802, 225803, 225805, 225809, 225955)
        AND r.starttime >= i.intime AND r.starttime <= i.outtime
    ) THEN 1 ELSE 0 END AS rrt
  FROM icu_stays i
  INNER JOIN cohort_admissions c
    ON i.hadm_id = c.hadm_id
  WHERE i.rn = 1
)

SELECT 
  CASE 
    WHEN los < 8 THEN '<8' 
    ELSE '>=8' 
  END AS los_group,
  COUNT(*) AS total_stays,
  ROUND(100 * SUM(mortality) / COUNT(*), 2) AS mortality_percent,
  ROUND(100 * SUM(mech_vent) / COUNT(*), 2) AS mech_vent_percent,
  ROUND(100 * SUM(vasopressor) / COUNT(*), 2) AS vasopressor_percent,
  ROUND(100 * SUM(rrt) / COUNT(*), 2) AS rrt_percent
FROM cohort_icu
GROUP BY los_group
ORDER BY los_group;