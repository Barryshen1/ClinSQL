WITH sepsis_admissions AS (
  -- Identify admissions with sepsis diagnosis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS admission_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),

cohort AS (
  -- Filter for male patients aged 80–90
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    sa.hadm_id,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag,
    sa.admission_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN sepsis_admissions sa
    ON p.subject_id = sa.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
),

first_icu_stay AS (
  -- Get first ICU stay for each admission
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

meds_first_24h AS (
  -- Medications in first 24 hours of ICU stay
  SELECT
    p.hadm_id,
    p.drug,
    p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN first_icu_stay icu
    ON p.hadm_id = icu.hadm_id
  WHERE p.starttime >= icu.intime
    AND p.starttime <= icu.intime + INTERVAL 24 HOUR
),

qt_drugs AS (
  SELECT 'amiodarone' AS drug UNION ALL
  SELECT 'sotalol' UNION ALL
  SELECT 'dofetilide' UNION ALL
  SELECT 'ibutilide' UNION ALL
  SELECT 'quinidine' UNION ALL
  SELECT 'procainamide' UNION ALL
  SELECT 'disopyramide' UNION ALL
  SELECT 'chlorpromazine' UNION ALL
  SELECT 'haloperidol' UNION ALL
  SELECT 'levofloxacin' UNION ALL
  SELECT 'moxifloxacin' UNION ALL
  SELECT 'ciprofloxacin' UNION ALL
  SELECT 'erythromycin' UNION ALL
  SELECT 'clarithromycin'
),

bleed_risk_drugs AS (
  SELECT 'warfarin' AS drug UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'enoxaparin' UNION ALL
  SELECT 'dalteparin' UNION ALL
  SELECT 'clopidogrel' UNION ALL
  SELECT 'ticagrelor' UNION ALL
  SELECT 'prasugrel' UNION ALL
  SELECT 'aspirin' UNION ALL
  SELECT 'rivaroxaban' UNION ALL
  SELECT 'apixaban' UNION ALL
  SELECT 'dabigatran'
),

med_flags AS (
  SELECT
    m.hadm_id,
    MAX(CASE WHEN qt.drug IS NOT NULL THEN 1 ELSE 0 END) AS has_qt_drug,
    MAX(CASE WHEN bleed.drug IS NOT NULL THEN 1 ELSE 0 END) AS has_bleed_drug
  FROM meds_first_24h m
  LEFT JOIN qt_drugs qt ON LOWER(m.drug) = LOWER(qt.drug)
  LEFT JOIN bleed_risk_drugs bleed ON LOWER(m.drug) = LOWER(bleed.drug)
  GROUP BY m.hadm_id
),

complexity_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(m.has_qt_drug, 0) AS has_qt_drug,
    COALESCE(m.has_bleed_drug, 0) AS has_bleed_drug,
    (COALESCE(m.has_qt_drug, 0) + COALESCE(m.has_bleed_drug, 0)) AS complexity_score
  FROM cohort c
  LEFT JOIN med_flags m ON c.hadm_id = m.hadm_id
),

ranked_scores AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY complexity_score) AS percentile_rank
  FROM complexity_scores
),

top_quartile AS (
  SELECT *
  FROM ranked_scores
  WHERE percentile_rank >= 0.75
)

-- Final output
SELECT
  -- Grouping
  CASE
    WHEN r.has_qt_drug = 1 AND r.has_bleed_drug = 1 THEN 'Both QT and Bleeding'
    ELSE 'Other'
  END AS drug_group,

  -- Complexity score distribution
  COUNT(*) AS patient_count,
  AVG(r.complexity_score) AS avg_complexity_score,
  APPROX_QUANTILES(r.complexity_score, 100)[OFFSET(25)] AS p25_score,
  APPROX_QUANTILES(r.complexity_score, 100)[OFFSET(50)] AS median_score,
  APPROX_QUANTILES(r.complexity_score, 100)[OFFSET(75)] AS p75_score,

  -- Percentile rank distribution
  AVG(r.percentile_rank) AS avg_percentile_rank,

  -- Outcomes for top quartile
  AVG(CASE WHEN t.hadm_id IS NOT NULL THEN r.admission_los ELSE NULL END) AS avg_los_top_quartile,
  AVG(CASE WHEN t.hadm_id IS NOT NULL THEN r.hospital_expire_flag ELSE NULL END) AS mortality_rate_top_quartile

FROM ranked_scores r
LEFT JOIN top_quartile t ON r.hadm_id = t.hadm_id
GROUP BY drug_group
ORDER BY drug_group;