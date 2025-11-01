WITH stroke_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CAST(DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS INT64) AS los_days,
    CASE
      WHEN REGEXP_CONTAINS(di.icd_code, r'^(433|434|436)') AND di.icd_version = 9 THEN 'ischemic'
      WHEN REGEXP_CONTAINS(di.icd_code, r'^(I63)') AND di.icd_version = 10 THEN 'ischemic'
      WHEN REGEXP_CONTAINS(di.icd_code, r'^(430|431|432)') AND di.icd_version = 9 THEN 'hemorrhagic'
      WHEN REGEXP_CONTAINS(di.icd_code, r'^(I60|I61|I62)') AND di.icd_version = 10 THEN 'hemorrhagic'
      ELSE NULL
    END AS stroke_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
),
stroke_filtered AS (
  SELECT DISTINCT
    subject_id,
    hadm_id,
    stroke_type,
    los_days,
    hospital_expire_flag
  FROM stroke_admissions
  WHERE stroke_type IS NOT NULL
),
comorbidity_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT CASE 
      -- exclude stroke diagnoses
      WHEN NOT REGEXP_CONTAINS(icd_code, r'^(430|431|432|433|434|436)$')
           AND NOT REGEXP_CONTAINS(icd_code, r'^(I60|I61|I62|I63)')
      THEN icd_code END) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
comorbidity_level AS (
  SELECT
    hadm_id,
    CASE
      WHEN comorb_count <= 1 THEN 'low'
      WHEN comorb_count <= 3 THEN 'med'
      ELSE 'high'
    END AS comorb_level
  FROM comorbidity_counts
),
icu_flags AS (
  SELECT
    sa.hadm_id,
    MAX(CASE WHEN d.category LIKE '%Vent%' OR d.label LIKE '%ventilation%' THEN 1 ELSE 0 END) AS mech_vent_flag,
    MAX(CASE WHEN LOWER(d.label) IN ('norepinephrine','epinephrine','dopamine','vasopressin','phenylephrine') THEN 1 ELSE 0 END) AS vaso_flag,
    MAX(CASE WHEN LOWER(d.label) LIKE '%dialysis%' OR LOWER(d.label) LIKE '%crrt%' THEN 1 ELSE 0 END) AS rrt_flag
  FROM stroke_filtered sa
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON sa.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON icu.stay_id = ie.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ie.itemid = d.itemid
  GROUP BY sa.hadm_id
),
final AS (
  SELECT
    sf.stroke_type,
    CASE WHEN sf.los_days <= 5 THEN '<=5' ELSE '>5' END AS los_category,
    cl.comorb_level,
    COUNT(*) AS total_cases,
    SUM(sf.hospital_expire_flag) AS deaths,
    SAFE_DIVIDE(SUM(sf.hospital_expire_flag), COUNT(*)) * 100 AS mortality_pct,
    APPROX_QUANTILES(sf.los_days, 100)[OFFSET(50)] AS median_los,
    SUM(icu.mech_vent_flag) AS mv_cases,
    SAFE_DIVIDE(SUM(icu.mech_vent_flag), COUNT(*)) * 100 AS mech_vent_pct,
    SUM(icu.vaso_flag) AS vaso_cases,
    SAFE_DIVIDE(SUM(icu.vaso_flag), COUNT(*)) * 100 AS vaso_pct,
    SUM(icu.rrt_flag) AS rrt_cases,
    SAFE_DIVIDE(SUM(icu.rrt_flag), COUNT(*)) * 100 AS rrt_pct
  FROM stroke_filtered sf
  LEFT JOIN comorbidity_level cl
    ON sf.hadm_id = cl.hadm_id
  LEFT JOIN icu_flags icu
    ON sf.hadm_id = icu.hadm_id
  GROUP BY sf.stroke_type, los_category, cl.comorb_level
)
SELECT *
FROM final
ORDER BY stroke_type, los_category, comorb_level;