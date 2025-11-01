WITH pneumonia_admissions AS (
  -- Select admissions for women aged 79-89 with pneumonia diagnosis, community-acquired
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    a.admission_location
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND LOWER(a.admission_location) NOT IN (
      'skilled nursing facility', 'rehab', 'nursing home', 'long term care hospital', 'intermediate care facility'
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        (
          -- ICD-10 pneumonia: J13-J18, J69
          (d.icd_version = 10 AND (
            REGEXP_CONTAINS(d.icd_code, '^J1[3-8]') OR d.icd_code LIKE 'J69%'
          ))
          -- ICD-9 pneumonia: 480-486, 507
          OR (d.icd_version = 9 AND (
            REGEXP_CONTAINS(d.icd_code, '^48[0-6]') OR d.icd_code LIKE '507%'
          ))
        )
    )
),
first_icu_stays AS (
  -- Get first ICU stay per admission
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime
  FROM (
    SELECT
      subject_id,
      hadm_id,
      MIN(intime) AS first_icu_intime
    FROM physionet-data.mimiciv_3_1_icu.icustays
    GROUP BY subject_id, hadm_id
  ) first
  JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON first.subject_id = i.subject_id
    AND first.hadm_id = i.hadm_id
    AND first.first_icu_intime = i.intime
),
admissions_with_icu AS (
  -- Merge pneumonia admissions with first ICU stay
  SELECT
    pa.*,
    fi.stay_id,
    fi.icu_intime,
    fi.icu_outtime,
    DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    CASE WHEN DATETIME_DIFF(fi.icu_intime, pa.admittime, HOUR) <= 24 THEN 1 ELSE 0 END AS day1_icu
  FROM pneumonia_admissions pa
  LEFT JOIN first_icu_stays fi
    ON pa.subject_id = fi.subject_id AND pa.hadm_id = fi.hadm_id
),
interventions AS (
  -- For each ICU stay, check for mech vent, vasopressor, RRT
  SELECT
    awi.subject_id,
    awi.hadm_id,
    awi.stay_id,
    -- Mechanical ventilation: chartevents/procedureevents itemids
    MAX(CASE WHEN ce.itemid IN (225792, 220339, 224685, 223848, 220862, 224688) THEN 1 ELSE 0 END) AS mech_vent,
    -- Vasopressors: inputevents itemids
    MAX(CASE WHEN ie.itemid IN (221906, 221289, 221662, 221653, 221749, 221986) THEN 1 ELSE 0 END) AS vasopressor,
    -- RRT: procedureevents itemids
    MAX(CASE WHEN pe.itemid IN (227558, 227560, 227561, 227562, 227565, 227566, 227567, 227568) THEN 1 ELSE 0 END) AS rrt
  FROM admissions_with_icu awi
  LEFT JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON awi.subject_id = ce.subject_id AND awi.hadm_id = ce.hadm_id AND awi.stay_id = ce.stay_id
    AND ce.charttime BETWEEN awi.icu_intime AND awi.icu_outtime
  LEFT JOIN physionet-data.mimiciv_3_1_icu.inputevents ie
    ON awi.subject_id = ie.subject_id AND awi.hadm_id = ie.hadm_id AND awi.stay_id = ie.stay_id
    AND ie.starttime BETWEEN awi.icu_intime AND awi.icu_outtime
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON awi.subject_id = pe.subject_id AND awi.hadm_id = pe.hadm_id AND awi.stay_id = pe.stay_id
    AND pe.starttime BETWEEN awi.icu_intime AND awi.icu_outtime
  GROUP BY awi.subject_id, awi.hadm_id, awi.stay_id
),
final AS (
  -- Merge interventions with admissions
  SELECT
    awi.subject_id,
    awi.hadm_id,
    awi.anchor_age,
    awi.gender,
    awi.los_days,
    CASE WHEN awi.los_days <= 7 THEN '<=7' ELSE '>7' END AS los_group,
    awi.day1_icu,
    awi.hospital_expire_flag,
    COALESCE(i.mech_vent, 0) AS mech_vent,
    COALESCE(i.vasopressor, 0) AS vasopressor,
    COALESCE(i.rrt, 0) AS rrt
  FROM admissions_with_icu awi
  LEFT JOIN interventions i
    ON awi.subject_id = i.subject_id AND awi.hadm_id = i.hadm_id AND awi.stay_id = i.stay_id
  WHERE awi.stay_id IS NOT NULL -- Only admissions with ICU stay
)
SELECT
  los_group,
  day1_icu,
  COUNT(*) AS n_admissions,
  ROUND(SUM(hospital_expire_flag) / COUNT(*), 3) AS mortality_rate,
  ROUND(SUM(mech_vent) / COUNT(*), 3) AS mech_vent_rate,
  ROUND(SUM(vasopressor) / COUNT(*), 3) AS vasopressor_rate,
  ROUND(SUM(rrt) / COUNT(*), 3) AS rrt_rate
FROM final
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;