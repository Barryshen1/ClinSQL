WITH
-- 1. Sepsis ICD codes (ICD-9 and ICD-10)
sepsis_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10: A40.*, A41.*, R65.2*
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^A40') OR
      REGEXP_CONTAINS(icd_code, r'^A41') OR
      REGEXP_CONTAINS(icd_code, r'^R652')
    ))
    -- ICD-9: 99591, 99592, 78552
    OR (icd_version = 9 AND (
      icd_code IN ('99591', '99592', '78552')
    ))
),

-- 2. Cohort: Male inpatients age 80-90 with sepsis
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN sepsis_icd s
    ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
),

-- 3. First ICU stay per admission
first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
cohort_icu AS (
  SELECT
    c.*,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los
  FROM cohort c
  JOIN first_icu_stay f
    ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
  WHERE f.rn = 1
),

-- 4. Drug risk lists (for demo, hardcoded arrays; in production, use external tables)
qt_drugs AS (
  SELECT drug FROM UNNEST([
    'amiodarone', 'sotalol', 'haloperidol', 'ciprofloxacin', 'levofloxacin', 'azithromycin', 'ondansetron', 'methadone'
  ]) AS drug
),
bleeding_drugs AS (
  SELECT drug FROM UNNEST([
    'warfarin', 'heparin', 'enoxaparin', 'aspirin', 'clopidogrel', 'apixaban', 'rivaroxaban', 'dabigatran'
  ]) AS drug
),

-- 5. Medications administered in first 24h of ICU stay
meds_24h AS (
  SELECT
    ci.subject_id,
    ci.hadm_id,
    ci.stay_id,
    LOWER(TRIM(pr.drug)) AS drug,
    pr.starttime
  FROM cohort_icu ci
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ci.subject_id = pr.subject_id AND ci.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= ci.intime
    AND pr.starttime < DATETIME_ADD(ci.intime, INTERVAL 24 HOUR)
),

-- 6. For each patient, flag QT and bleeding risk exposure, and compute complexity score
patient_meds AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    COUNT(DISTINCT m.drug) AS complexity_score,
    MAX(IF(qt.drug IS NOT NULL, 1, 0)) AS has_qt,
    MAX(IF(bleed.drug IS NOT NULL, 1, 0)) AS has_bleed
  FROM meds_24h m
  LEFT JOIN qt_drugs qt ON m.drug = qt.drug
  LEFT JOIN bleeding_drugs bleed ON m.drug = bleed.drug
  GROUP BY m.subject_id, m.hadm_id, m.stay_id
),

-- 7. Merge with cohort ICU info
cohort_final AS (
  SELECT
    ci.*,
    pm.complexity_score,
    pm.has_qt,
    pm.has_bleed
  FROM cohort_icu ci
  LEFT JOIN patient_meds pm
    ON ci.subject_id = pm.subject_id AND ci.hadm_id = pm.hadm_id AND ci.stay_id = pm.stay_id
),

-- 8. Calculate percentiles and groupings
complexity_stats AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY complexity_score) AS percentile_rank,
    CASE
      WHEN has_qt = 1 AND has_bleed = 1 THEN 'QT+Bleed'
      ELSE 'Other'
    END AS risk_group
  FROM cohort_final
),

-- 9. Get 75th percentile cutoff
percentile_cutoff AS (
  SELECT
    APPROX_QUANTILES(complexity_score, 4)[OFFSET(3)] AS q3_score
  FROM complexity_stats
  WHERE complexity_score IS NOT NULL
)

-- Final output: Distribution, percentile ranks, LOS/mortality for top quartile
SELECT
  cs.risk_group,
  cs.complexity_score,
  cs.percentile_rank,
  COUNT(*) OVER (PARTITION BY cs.risk_group, cs.complexity_score) AS n_patients_with_score,
  -- Top quartile LOS/mortality
  CASE WHEN cs.complexity_score >= pc.q3_score THEN cs.los ELSE NULL END AS los_top_quartile,
  CASE WHEN cs.complexity_score >= pc.q3_score THEN cs.hospital_expire_flag ELSE NULL END AS mortality_top_quartile
FROM complexity_stats cs
CROSS JOIN percentile_cutoff pc
ORDER BY cs.risk_group, cs.complexity_score;