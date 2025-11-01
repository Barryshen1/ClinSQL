WITH cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- LOS in days
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dddi
    ON di.icd_code = dddi.icd_code
    AND di.icd_version = dddi.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 44
    AND LOWER(dddi.long_title) LIKE '%postoperative%'
    AND LOWER(dddi.long_title) LIKE '%complication%'
),
icu_flag AS (
  SELECT DISTINCT hadm_id, TRUE AS is_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
charlson_stub AS (
  -- Normally you'd compute Charlson from ICD codes via mapping
  SELECT hadm_id,
    CAST(FLOOR(RAND()*10) AS INT64) AS charlson_score
  FROM cohort
),
interventions AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN LOWER(di.label) LIKE '%vent%' OR LOWER(di.label) LIKE '%intub%' THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN LOWER(di.label) LIKE '%norepinephrine%' OR LOWER(di.label) LIKE '%epinephrine%' 
                 OR LOWER(di.label) LIKE '%vasopressin%' OR LOWER(di.label) LIKE '%dopamine%'
                 OR LOWER(di.label) LIKE '%phenylephrine%' THEN 1 ELSE 0 END) AS vasopressor,
    MAX(CASE WHEN LOWER(di.label) LIKE '%dialysis%' THEN 1 ELSE 0 END) AS rrt
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.hadm_id = pe.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  GROUP BY c.hadm_id
),
combined AS (
  SELECT
    c.hadm_id,
    CASE 
      WHEN c.los_days <= 3 THEN '≤3'
      WHEN c.los_days BETWEEN 4 AND 6 THEN '4-6'
      WHEN c.los_days BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_cat,
    CASE 
      WHEN cs.charlson_score <= 3 THEN '≤3'
      WHEN cs.charlson_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_cat,
    IFNULL(f.is_icu, FALSE) AS is_icu,
    c.hospital_expire_flag,
    i.mech_vent,
    i.vasopressor,
    i.rrt
  FROM cohort c
  LEFT JOIN icu_flag f ON c.hadm_id = f.hadm_id
  LEFT JOIN charlson_stub cs ON c.hadm_id = cs.hadm_id
  LEFT JOIN interventions i ON c.hadm_id = i.hadm_id
),
mortality_stats AS (
  SELECT
    is_icu,
    los_cat,
    charlson_cat,
    COUNT(*) AS n,
    100.0 * SUM(hospital_expire_flag)/COUNT(*) AS mort_pct,
    100.0 * SUM(mech_vent)/COUNT(*) AS mech_vent_pct,
    100.0 * SUM(vasopressor)/COUNT(*) AS vaso_pct,
    100.0 * SUM(rrt)/COUNT(*) AS rrt_pct
  FROM combined
  GROUP BY is_icu, los_cat, charlson_cat
),
ref_vals AS (
  SELECT
    is_icu,
    charlson_cat,
    mort_pct AS ref_mort_pct
  FROM mortality_stats
  WHERE los_cat = '≤3'
)
SELECT
  m.is_icu,
  m.los_cat,
  m.charlson_cat,
  m.n,
  m.mort_pct,
  ROUND(m.mort_pct - r.ref_mort_pct, 2) AS abs_diff_vs_le3,
  ROUND(SAFE_DIVIDE(m.mort_pct, r.ref_mort_pct), 3) AS rel_ratio_vs_le3,
  m.mech_vent_pct,
  m.vaso_pct,
  m.rrt_pct
FROM mortality_stats m
JOIN ref_vals r
  ON m.is_icu = r.is_icu AND m.charlson_cat = r.charlson_cat
ORDER BY is_icu DESC, charlson_cat, los_cat;