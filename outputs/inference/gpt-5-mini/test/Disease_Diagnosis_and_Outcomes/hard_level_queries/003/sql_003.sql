WITH
-- first ICU stay (if any) per admission
icu_first AS (
  SELECT
    hadm_id,
    ARRAY_AGG(stay_id ORDER BY intime LIMIT 1)[SAFE_OFFSET(0)] AS stay_id,
    MIN(intime) AS icu_intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

-- vital signs: earliest value within 24 hours of ICU intime for each metric (if ICU stay exists)
vitals_24h AS (
  SELECT
    f.hadm_id,
    -- earliest heart rate
    ARRAY_AGG(CASE WHEN LOWER(di.label) LIKE '%heart rate%' THEN ce.valuenum END ORDER BY ce.charttime LIMIT 1)[SAFE_OFFSET(0)] AS hr_first,
    -- earliest systolic BP (label contains 'systolic' and 'pressure' or 'bp')
    ARRAY_AGG(CASE WHEN LOWER(di.label) LIKE '%systolic%' AND (LOWER(di.label) LIKE '%bp%' OR LOWER(di.label) LIKE '%blood pressure%') THEN ce.valuenum END ORDER BY ce.charttime LIMIT 1)[SAFE_OFFSET(0)] AS sbp_first,
    -- earliest resp rate
    ARRAY_AGG(CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%resp rate%' THEN ce.valuenum END ORDER BY ce.charttime LIMIT 1)[SAFE_OFFSET(0)] AS rr_first,
    -- earliest SpO2 / oxygen saturation
    ARRAY_AGG(CASE WHEN LOWER(di.label) LIKE '%oxygen saturation%' OR LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%o2 sat%' THEN ce.valuenum END ORDER BY ce.charttime LIMIT 1)[SAFE_OFFSET(0)] AS spo2_first
  FROM
    icu_first f
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ce.stay_id = f.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    -- only within first 24h of ICU intime
    ce.charttime BETWEEN f.icu_intime AND TIMESTAMP_ADD(f.icu_intime, INTERVAL 24 HOUR)
    -- numeric values only
    AND ce.valuenum IS NOT NULL
  GROUP BY f.hadm_id
),

-- baseline 90-day mortality for all female inpatients aged 70-80 (all admissions)
baseline_female_70_80 AS (
  SELECT
    COUNT(1) AS n_total,
    SUM(CASE
          WHEN p.dod IS NOT NULL
           AND DATE_DIFF(DATE(p.dod), DATE(a.admittime), DAY) BETWEEN 0 AND 90
          THEN 1 ELSE 0 END) AS deaths_90d,
    SAFE_DIVIDE(
      SUM(CASE
            WHEN p.dod IS NOT NULL
             AND DATE_DIFF(DATE(p.dod), DATE(a.admittime), DAY) BETWEEN 0 AND 90
            THEN 1 ELSE 0 END),
      COUNT(1)
    ) AS pct_90d
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),

-- cohort: admissions for female patients 70-80 with pulmonary embolism diagnosis in that admission
pe_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- attach first ICU info if any
    f.stay_id AS icu_stay_id,
    f.icu_intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    LEFT JOIN icu_first f
      ON a.hadm_id = f.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      -- pulmonary embolism diagnosis on this admission (any ICD version) via long_title keyword
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%pulmonary embol%'
    )
),

-- augment cohort with comorbidity flags, vitals flags, outcomes
pe_features AS (
  SELECT
    c.*,
    -- comorbidity flags based on admission diagnoses (long_title keyword matching)
    CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = c.hadm_id
          AND LOWER(dd.long_title) LIKE '%malignant%'
    ) THEN 1 ELSE 0 END AS has_malignancy,
    CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = c.hadm_id
          AND LOWER(dd.long_title) LIKE '%heart failure%'
    ) THEN 1 ELSE 0 END AS has_heart_failure,
    CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = c.hadm_id
          AND (
            LOWER(dd.long_title) LIKE '%chronic obstructive%' OR
            LOWER(dd.long_title) LIKE '%chronic respiratory%' OR
            LOWER(dd.long_title) LIKE '%chronic lung%' OR
            LOWER(dd.long_title) LIKE '%emphysema%' OR
            LOWER(dd.long_title) LIKE '%chronic bronchitis%' OR
            LOWER(dd.long_title) LIKE '%copd%'
          )
    ) THEN 1 ELSE 0 END AS has_chronic_pulm,
    -- AKI and ARDS diagnosis during admission
    CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = c.hadm_id
          AND (
            LOWER(dd.long_title) LIKE '%acute kidney%' OR
            LOWER(dd.long_title) LIKE '%acute renal%' OR
            LOWER(dd.long_title) LIKE '%acute kidney injury%'
          )
    ) THEN 1 ELSE 0 END AS has_aki,
    CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE d.hadm_id = c.hadm_id
          AND (
            LOWER(dd.long_title) LIKE '%acute respiratory distress%' OR
            LOWER(dd.long_title) LIKE '%acute respiratory distress syndrome%' OR
            LOWER(dd.long_title) LIKE '%ards%'
          )
    ) THEN 1 ELSE 0 END AS has_ards,
    -- 90-day mortality (post-admission)
    CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.patients` p
        WHERE p.subject_id = c.subject_id
          AND p.dod IS NOT NULL
          AND DATE_DIFF(DATE(p.dod), DATE(c.admittime), DAY) BETWEEN 0 AND 90
    ) THEN 1 ELSE 0 END AS died_within_90d
  FROM
    pe_cohort c
),

-- combine vitals into the cohort
pe_with_vitals AS (
  SELECT
    pf.*,
    v.hr_first,
    v.sbp_first,
    v.rr_first,
    v.spo2_first,
    -- physiologic abnormality flags (if vitals missing -> 0)
    CASE WHEN v.hr_first IS NOT NULL AND v.hr_first >= 110 THEN 1 ELSE 0 END AS flag_tachycardia,
    CASE WHEN v.sbp_first IS NOT NULL AND v.sbp_first < 100 THEN 1 ELSE 0 END AS flag_hypotension,
    CASE WHEN v.rr_first IS NOT NULL AND v.rr_first >= 30 THEN 1 ELSE 0 END AS flag_tachypnea,
    CASE WHEN v.spo2_first IS NOT NULL AND v.spo2_first < 90 THEN 1 ELSE 0 END AS flag_hypoxemia
  FROM
    pe_features pf
    LEFT JOIN vitals_24h v
      ON pf.hadm_id = v.hadm_id
),

-- compute a simple additive risk score and assign quintiles
pe_scored AS (
  SELECT
    *,
    -- additive risk score: comorbidity flags + physiologic flags
    (has_malignancy
     + has_heart_failure
     + has_chronic_pulm
     + flag_tachycardia
     + flag_hypotension
     + flag_tachypnea
     + flag_hypoxemia) AS risk_score
  FROM
    pe_with_vitals
),

-- assign quintiles (1 = lowest risk score group, 5 = highest)
pe_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM
    pe_scored
)

-- Final aggregation per quintile
SELECT
  q.risk_quintile AS quintile,
  COUNT(1) AS n_admissions,
  -- 90-day mortality in cohort per quintile
  SAFE_DIVIDE(SUM(q.died_within_90d), COUNT(1)) AS pct_90d_mortality,
  -- baseline 90-day mortality for all female 70-80 patients (comparison)
  bf.pct_90d AS baseline_female_70_80_pct_90d,
  -- AKI and ARDS rates within the admission
  SAFE_DIVIDE(SUM(q.has_aki), COUNT(1)) AS pct_aki,
  SAFE_DIVIDE(SUM(q.has_ards), COUNT(1)) AS pct_ards,
  -- median hospital LOS (days) among survivors (hospital_expire_flag = 0)
  -- using APPROX_QUANTILES to get approximate median
  APPROX_QUANTILES(
    CASE WHEN q.hospital_expire_flag = 0 AND q.dischtime IS NOT NULL
         THEN TIMESTAMP_DIFF(q.dischtime, q.admittime, DAY) ELSE NULL END,
    2
  )[SAFE_OFFSET(1)] AS median_survivor_los_days
FROM
  pe_quintiles q
  CROSS JOIN baseline_female_70_80 bf
GROUP BY
  q.risk_quintile,
  bf.pct_90d
ORDER BY
  q.risk_quintile;