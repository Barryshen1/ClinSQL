WITH
-- 1. Female inpatients aged 40-50
female_40_50 AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

-- 2. ARDS admissions (ICD-9: 518.82, ICD-10: J80)
ards_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE ( (d.icd_version = 9 AND d.icd_code = '51882')
       OR (d.icd_version = 10 AND d.icd_code = 'J80') )
),

-- 3. ARDS ICU stays for female 40-50
ards_icu_stays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN female_40_50 f ON icu.subject_id = f.subject_id
  JOIN ards_admissions a ON icu.subject_id = a.subject_id AND icu.hadm_id = a.hadm_id
),

-- 4. Non-ARDS ICU stays for female 40-50
non_ards_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_40_50 f ON a.subject_id = f.subject_id
  WHERE NOT EXISTS (
    SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
      AND ( (d.icd_version = 9 AND d.icd_code = '51882')
         OR (d.icd_version = 10 AND d.icd_code = 'J80') )
  )
),

non_ards_icu_stays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN non_ards_admissions na ON icu.subject_id = na.subject_id AND icu.hadm_id = na.hadm_id
),

-- 5. Critical lab events in first 72h of ICU stay
critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    icu.stay_id,
    COUNTIF(
      (
        (l.flag = 'abnormal')
        OR
        (SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL
          AND (
            (SAFE_CAST(l.ref_range_lower AS FLOAT64) IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64))
            OR
            (SAFE_CAST(l.ref_range_upper AS FLOAT64) IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64))
          )
        )
      )
    ) AS critical_lab_events
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON l.subject_id = icu.subject_id AND l.hadm_id = icu.hadm_id
  WHERE l.charttime >= icu.intime
    AND l.charttime < DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY l.subject_id, l.hadm_id, icu.stay_id
),

-- 6. ARDS ICU stays with critical lab events
ards_icu_labscore AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    a.intime,
    a.outtime,
    a.los,
    COALESCE(cl.critical_lab_events, 0) AS lab_instability_score
  FROM ards_icu_stays a
  LEFT JOIN critical_labs cl
    ON a.subject_id = cl.subject_id AND a.hadm_id = cl.hadm_id AND a.stay_id = cl.stay_id
),

-- 7. Non-ARDS ICU stays with critical lab events
non_ards_icu_labscore AS (
  SELECT
    n.subject_id,
    n.hadm_id,
    n.stay_id,
    n.intime,
    n.outtime,
    n.los,
    COALESCE(cl.critical_lab_events, 0) AS lab_instability_score
  FROM non_ards_icu_stays n
  LEFT JOIN critical_labs cl
    ON n.subject_id = cl.subject_id AND n.hadm_id = cl.hadm_id AND n.stay_id = cl.stay_id
),

-- 8. 75th percentile threshold for ARDS cohort
ards_labscore_percentile AS (
  SELECT
    APPROX_QUANTILES(lab_instability_score, 100)[75] AS labscore_75th
  FROM ards_icu_labscore
),

-- 9. ARDS patients at/above 75th percentile
ards_high_labscore AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    a.lab_instability_score,
    a.los
  FROM ards_icu_labscore a
  CROSS JOIN ards_labscore_percentile p
  WHERE a.lab_instability_score >= p.labscore_75th
),

-- 10. Mortality for ARDS high-score patients
ards_high_labscore_mortality AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.stay_id,
    h.lab_instability_score,
    h.los,
    adm.hospital_expire_flag
  FROM ards_high_labscore h
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON h.subject_id = adm.subject_id AND h.hadm_id = adm.hadm_id
)

-- Final output
SELECT
  -- 1. 75th percentile threshold
  (SELECT labscore_75th FROM ards_labscore_percentile) AS labscore_75th_percentile,

  -- 2. ARDS patients at/above threshold: mortality, mean LOS, mean critical lab events
  (SELECT
      ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 3)
    FROM ards_high_labscore_mortality
  ) AS ards_highscore_mortality_rate,

  (SELECT
      ROUND(AVG(los), 2)
    FROM ards_high_labscore_mortality
  ) AS ards_highscore_mean_los,

  (SELECT
      ROUND(AVG(lab_instability_score), 2)
    FROM ards_high_labscore_mortality
  ) AS ards_highscore_mean_lab_events,

  -- 3. Age-matched non-ARDS: mean critical lab events per patient
  (SELECT
      ROUND(AVG(lab_instability_score), 2)
    FROM non_ards_icu_labscore
  ) AS non_ards_mean_lab_events;