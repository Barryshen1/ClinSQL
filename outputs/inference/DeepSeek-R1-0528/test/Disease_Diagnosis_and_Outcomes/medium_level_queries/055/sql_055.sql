WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital,
    adm.hospital_expire_flag,
    p.gender,
    (EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 71 AND 81
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_version = 10
        AND REGEXP_CONTAINS(icd_code, '^T8[0-8]')
    )
),

cohort_icu_flag AS (
  SELECT 
    c.*,
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag
  FROM cohort c
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON c.hadm_id = i.hadm_id
),

interventions AS (
  SELECT 
    c.hadm_id,  -- Explicit table alias to resolve ambiguity
    MAX(CASE WHEN proc.icd_code IN ('5A1935Z', '5A1945Z', '5A1955Z') AND proc.icd_version = 10 THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(pres.drug), 'norepinephrine|epinephrine|dopamine|vasopressin|phenylephrine') THEN 1 ELSE 0 END) AS vasopressor,
    MAX(CASE WHEN proc.icd_code IN ('5A1D60Z', '5A1D70Z', '5A1D80Z', '5A1D90Z') AND proc.icd_version = 10 THEN 1 ELSE 0 END) AS rrt
  FROM cohort_icu_flag c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
    ON c.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres 
    ON c.hadm_id = pres.hadm_id
  GROUP BY c.hadm_id  -- Explicit table alias
),

final_cohort AS (
  SELECT 
    c.*,
    COALESCE(i.mech_vent, 0) AS mech_vent,
    COALESCE(i.vasopressor, 0) AS vasopressor,
    COALESCE(i.rrt, 0) AS rrt
  FROM cohort_icu_flag c
  LEFT JOIN interventions i 
    ON c.hadm_id = i.hadm_id
),

quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (PARTITION BY icu_flag ORDER BY los_hospital) AS los_quartile
  FROM final_cohort
),

mortality_agg AS (
  SELECT 
    icu_flag,
    los_quartile,
    COUNT(*) AS total_admissions,
    SUM(hospital_expire_flag) AS mortality_count,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(mech_vent) * 100 AS mech_vent_pct,
    AVG(vasopressor) * 100 AS vasopressor_pct,
    AVG(rrt) * 100 AS rrt_pct
  FROM quartiles
  GROUP BY icu_flag, los_quartile
)

SELECT 
  CASE icu_flag WHEN 1 THEN 'ICU' ELSE 'Non-ICU' END AS patient_group,
  los_quartile,
  total_admissions,
  mortality_count,
  ROUND(mortality_rate, 4) AS mortality_rate,
  ROUND(mortality_rate - FIRST_VALUE(mortality_rate) OVER (PARTITION BY icu_flag ORDER BY los_quartile), 4) AS mortality_abs_diff_vs_q1,
  ROUND(mortality_rate / FIRST_VALUE(mortality_rate) OVER (PARTITION BY icu_flag ORDER BY los_quartile), 4) AS mortality_rel_risk_vs_q1,
  ROUND(mech_vent_pct, 2) AS mech_vent_pct,
  ROUND(vasopressor_pct, 2) AS vasopressor_pct,
  ROUND(rrt_pct, 2) AS rrt_pct
FROM mortality_agg
ORDER BY patient_group, los_quartile;