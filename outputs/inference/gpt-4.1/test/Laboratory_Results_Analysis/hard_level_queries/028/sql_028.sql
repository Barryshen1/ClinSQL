WITH ich_icd_codes AS (
  -- ICD-10: I60.x, I61.x, I62.x; ICD-9: 430, 431, 432.x
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I60') OR
      REGEXP_CONTAINS(icd_code, r'^I61') OR
      REGEXP_CONTAINS(icd_code, r'^I62')
    ))
    OR
    (icd_version = 9 AND (
      icd_code = '430' OR
      icd_code = '431' OR
      REGEXP_CONTAINS(icd_code, r'^432')
    ))
),
ich_admissions AS (
  -- Admissions with ICH diagnosis
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN ich_icd_codes icd
    ON dx.icd_code = icd.icd_code AND dx.icd_version = icd.icd_version
),
target_patients AS (
  -- Women aged 74-84 with ICH
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 74 AND 84
),
ich_cohort AS (
  SELECT ia.subject_id, ia.hadm_id
  FROM ich_admissions ia
  JOIN target_patients tp ON ia.subject_id = tp.subject_id
),
controls AS (
  -- Women aged 74-84, no ICH diagnosis
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN target_patients tp ON adm.subject_id = tp.subject_id
  WHERE adm.hadm_id NOT IN (SELECT hadm_id FROM ich_admissions)
),
first_icu_stays AS (
  -- First ICU stay per admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
),
ich_first_icu AS (
  SELECT f.*
  FROM first_icu_stays f
  JOIN ich_cohort c ON f.subject_id = c.subject_id AND f.hadm_id = c.hadm_id
  WHERE f.rn = 1
),
controls_first_icu AS (
  SELECT f.*
  FROM first_icu_stays f
  JOIN controls c ON f.subject_id = c.subject_id AND f.hadm_id = c.hadm_id
  WHERE f.rn = 1
),
lab_instability AS (
  -- For each ICH patient, count distinct abnormal labs in first 72h
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    COUNT(DISTINCT l.itemid) AS lab_instability,
    SUM(CASE
      WHEN l.flag = 'critical'
        OR (l.valuenum IS NOT NULL AND (
          (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower) OR
          (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
        ) AND (
          -- "critical" if >20% outside reference range
          (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower * 0.8) OR
          (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper * 1.2)
        ))
      THEN 1 ELSE 0 END
    ) AS critical_lab_count
  FROM ich_first_icu icu
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON icu.subject_id = l.subject_id AND icu.hadm_id = l.hadm_id
    AND l.charttime >= icu.intime AND l.charttime < DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL
  WHERE
    -- abnormal: outside reference range
    (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),
controls_lab_instability AS (
  -- For controls
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    COUNT(DISTINCT l.itemid) AS lab_instability,
    SUM(CASE
      WHEN l.flag = 'critical'
        OR (l.valuenum IS NOT NULL AND (
          (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower) OR
          (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
        ) AND (
          (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower * 0.8) OR
          (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper * 1.2)
        ))
      THEN 1 ELSE 0 END
    ) AS critical_lab_count
  FROM controls_first_icu icu
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON icu.subject_id = l.subject_id AND icu.hadm_id = l.hadm_id
    AND l.charttime >= icu.intime AND l.charttime < DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL
  WHERE
    (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),
ich_outcomes AS (
  -- Merge with outcomes
  SELECT
    li.subject_id,
    li.hadm_id,
    li.stay_id,
    li.lab_instability,
    li.critical_lab_count,
    icu.los,
    adm.hospital_expire_flag
  FROM lab_instability li
  JOIN ich_first_icu icu
    ON li.subject_id = icu.subject_id AND li.hadm_id = icu.hadm_id AND li.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON li.hadm_id = adm.hadm_id
),
controls_outcomes AS (
  SELECT
    li.subject_id,
    li.hadm_id,
    li.stay_id,
    li.lab_instability,
    li.critical_lab_count,
    icu.los,
    adm.hospital_expire_flag
  FROM controls_lab_instability li
  JOIN controls_first_icu icu
    ON li.subject_id = icu.subject_id AND li.hadm_id = icu.hadm_id AND li.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON li.hadm_id = adm.hadm_id
),
ich_quintiles AS (
  -- Assign quintiles by lab instability
  SELECT *,
    NTILE(5) OVER (ORDER BY lab_instability) AS instability_quintile
  FROM ich_outcomes
)
SELECT
  instability_quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(lab_instability),1) AS mean_lab_instability,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)),3) AS mortality_rate,
  ROUND(AVG(los),2) AS mean_icu_los,
  ROUND(SUM(critical_lab_count)/COUNT(*),2) AS mean_critical_lab_count,
  -- Compare to controls: mean critical lab count in controls
  (
    SELECT ROUND(AVG(critical_lab_count),2)
    FROM controls_outcomes
  ) AS controls_mean_critical_lab_count
FROM ich_quintiles
GROUP BY instability_quintile
ORDER BY instability_quintile;