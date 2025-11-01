WITH pe_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN ('I260', 'I269') -- ICD-10 codes for PE
        AND icd_version = 10
    )
),

-- Approximate comorbidity score using DRG severity (1–4)
comorbidity_scores AS (
  SELECT
    pp.subject_id,
    pp.hadm_id,
    MAX(drg.drg_severity) AS comorbidity_score
  FROM pe_patients pp
  JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    ON pp.hadm_id = drg.hadm_id
  WHERE drg.drg_severity IS NOT NULL
  GROUP BY pp.subject_id, pp.hadm_id
),

-- Complications: Cardiovascular or Neurologic
complications AS (
  SELECT
    di.hadm_id,
    MAX(CASE
      WHEN di.icd_code IN ('I63', 'I64', 'G45') THEN 1 -- Stroke/TIA
      WHEN di.icd_code IN ('I21', 'I22') THEN 1 -- MI
      ELSE 0
    END) AS has_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.icd_version = 10
    AND di.icd_code IN ('I63', 'I64', 'G45', 'I21', 'I22')
  GROUP BY di.hadm_id
),

-- Final cohort with outcomes
final_cohort AS (
  SELECT
    pp.*,
    cs.comorbidity_score,
    COALESCE(c.has_complication, 0) AS has_complication,
    CASE
      WHEN pp.deathtime IS NOT NULL
        OR (pp.hospital_expire_flag = 1)
        OR (DATETIME_DIFF(pp.dischtime, pp.admittime, DAY) <= 30
            AND pp.deathtime IS NOT NULL)
      THEN 1
      ELSE 0
    END AS mortality_30day
  FROM pe_patients pp
  JOIN comorbidity_scores cs
    ON pp.hadm_id = cs.hadm_id
  LEFT JOIN complications c
    ON pp.hadm_id = c.hadm_id
),

-- General inpatients (same age/gender)
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- Aggregated results
results AS (
  SELECT
    AVG(fc.comorbidity_score) AS mean_comorbidity_score,
    AVG(fc.mortality_30day) AS mortality_30day_rate,
    AVG(CASE WHEN fc.has_complication = 1 THEN 1.0 ELSE 0.0 END) AS complication_rate,
    AVG(CASE WHEN fc.mortality_30day = 0 THEN fc.los_days ELSE NULL END) AS survivor_mean_los,
    APPROX_QUANTILES(gi.los_days, 100)[OFFSET(50)] AS general_median_los
  FROM final_cohort fc
  CROSS JOIN general_inpatients gi
)

SELECT * FROM results;