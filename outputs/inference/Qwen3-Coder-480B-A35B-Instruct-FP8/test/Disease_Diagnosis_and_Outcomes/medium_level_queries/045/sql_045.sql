WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN 'LOS ≤7'
      ELSE 'LOS >7'
    END AS los_group,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = a.hadm_id
          AND icu.intime <= DATETIME_ADD(a.admittime, INTERVAL 1 DAY)
      ) THEN 1
      ELSE 0
    END AS icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
      WHERE dx.hadm_id = a.hadm_id
        AND (
          LOWER(d.long_title) LIKE '%community%acquired%pneumonia%'
          OR LOWER(d.long_title) LIKE '%aspiration%pneumonia%'
          OR LOWER(d.long_title) LIKE '%pneumonia%aspiration%'
        )
    )
),

mech_vent AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  JOIN `physionet-data.mimiciv_3_1_icu.d_items`
    USING (itemid)
  WHERE LOWER(label) LIKE '%mechanical%ventilator%'
     OR LOWER(label) LIKE '%ventilator%'
),

vasopressors AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) IN (
    'norepinephrine', 'dopamine', 'epinephrine', 'phenylephrine', 'vasopressin'
  )
),

rrt AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  JOIN `physionet-data.mimiciv_3_1_icu.d_items`
    USING (itemid)
  WHERE LOWER(label) LIKE '%dialysis%'
     OR LOWER(label) LIKE '%crrt%'
     OR LOWER(label) LIKE '%hemodialysis%'
)

SELECT
  los_group,
  icu_day1,
  COUNT(*) AS total_admissions,
  AVG(hospital_expire_flag) AS in_hosp_mortality,
  AVG(CASE WHEN icu_day1 = 1 THEN 1 ELSE 0 END) AS pct_icu_day1,
  AVG(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS pct_mech_vent,
  AVG(CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS pct_vasopressor,
  AVG(CASE WHEN rt.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS pct_rrt
FROM cohort
LEFT JOIN mech_vent mv USING (hadm_id)
LEFT JOIN vasopressors vp USING (hadm_id)
LEFT JOIN rrt rt USING (hadm_id)
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;