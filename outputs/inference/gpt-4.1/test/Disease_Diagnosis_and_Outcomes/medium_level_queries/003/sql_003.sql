WITH stroke_codes AS (
  -- Define ischemic and hemorrhagic stroke ICD codes
  SELECT 'ischemic' AS stroke_type, 'I63' AS icd_prefix, 10 AS icd_version UNION ALL
  SELECT 'ischemic', '433', 9 UNION ALL
  SELECT 'ischemic', '434', 9 UNION ALL
  SELECT 'hemorrhagic', 'I61', 10 UNION ALL
  SELECT 'hemorrhagic', 'I60', 10 UNION ALL
  SELECT 'hemorrhagic', '430', 9 UNION ALL
  SELECT 'hemorrhagic', '431', 9
),
stroke_admissions AS (
  -- Find admissions with ischemic or hemorrhagic stroke
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
        JOIN stroke_codes sc ON di.icd_version = sc.icd_version
        WHERE di.hadm_id = d.hadm_id AND di.icd_code LIKE CONCAT(sc.icd_prefix, '%') AND sc.stroke_type = 'ischemic'
      ) THEN 'ischemic'
      WHEN EXISTS (
        SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
        JOIN stroke_codes sc ON di.icd_version = sc.icd_version
        WHERE di.hadm_id = d.hadm_id AND di.icd_code LIKE CONCAT(sc.icd_prefix, '%') AND sc.stroke_type = 'hemorrhagic'
      ) THEN 'hemorrhagic'
      ELSE NULL
    END AS stroke_type
  FROM physionet-data.mimiciv_3_1_hosp.admissions d
),
filtered_admissions AS (
  -- Filter for men aged 44–54 with stroke
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stroke_type
  FROM stroke_admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.stroke_type IS NOT NULL
),
comorbidity_counts AS (
  -- Count unique comorbidities per admission (excluding stroke codes)
  SELECT
    d.subject_id,
    d.hadm_id,
    COUNT(DISTINCT CASE
      WHEN NOT (
        (d.icd_version = 10 AND (d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I60%'))
        OR (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '430%' OR d.icd_code LIKE '431%'))
      )
      THEN d.icd_code
      ELSE NULL
    END) AS n_comorbid
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  GROUP BY d.subject_id, d.hadm_id
),
admission_los AS (
  -- Calculate LOS and mortality per admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stroke_type,
    ad.admittime,
    ad.dischtime,
    ad.hospital_expire_flag,
    DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los
  FROM filtered_admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.admissions ad
    ON a.hadm_id = ad.hadm_id
),
admission_comorbidity AS (
  -- Merge LOS and comorbidity
  SELECT
    al.*,
    COALESCE(cc.n_comorbid, 0) AS n_comorbid,
    CASE
      WHEN COALESCE(cc.n_comorbid, 0) <= 1 THEN 'low'
      WHEN COALESCE(cc.n_comorbid, 0) <= 3 THEN 'medium'
      ELSE 'high'
    END AS comorbidity_group,
    CASE
      WHEN al.los <= 5 THEN '≤5'
      ELSE '>5'
    END AS los_group
  FROM admission_los al
  LEFT JOIN comorbidity_counts cc
    ON al.subject_id = cc.subject_id AND al.hadm_id = cc.hadm_id
),
icu_stays AS (
  -- Get ICU stays per admission
  SELECT
    stay_id,
    subject_id,
    hadm_id
  FROM physionet-data.mimiciv_3_1_icu.icustays
),
vent_patients AS (
  -- Identify admissions with mechanical ventilation (any ICU stay)
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id
  FROM icu_stays i
  JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON i.stay_id = pe.stay_id
  WHERE pe.itemid IN (
    -- Common ventilation itemids (example: 225792, 224687, 224688, 224689, 224690, 224691, 224692, 224693, 224694, 224695, 224696, 224697)
    225792, 224687, 224688, 224689, 224690, 224691, 224692, 224693, 224694, 224695, 224696, 224697
  )
),
vasopressor_patients AS (
  -- Identify admissions with vasopressors (any ICU stay)
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id
  FROM icu_stays i
  JOIN physionet-data.mimiciv_3_1_icu.inputevents ie
    ON i.stay_id = ie.stay_id
  WHERE ie.itemid IN (
    -- Common vasopressor itemids (example: norepinephrine, epinephrine, vasopressin, dopamine, phenylephrine)
    221906, 221289, 221662, 221653, 221749
  )
),
rrt_patients AS (
  -- Identify admissions with RRT (any ICU stay)
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id
  FROM icu_stays i
  JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON i.stay_id = pe.stay_id
  WHERE pe.itemid IN (
    -- Common RRT itemids (example: CRRT, hemodialysis)
    227558, 227560, 227561, 227562, 227563, 227564
  )
),
final AS (
  SELECT
    ac.stroke_type,
    ac.los_group,
    ac.comorbidity_group,
    COUNT(*) AS n_patients,
    100.0 * SUM(CASE WHEN ac.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_pct,
    APPROX_QUANTILES(ac.los, 2)[OFFSET(1)] AS median_los,
    100.0 * SUM(CASE WHEN vp.subject_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS mech_vent_pct,
    100.0 * SUM(CASE WHEN vsp.subject_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS vasopressor_pct,
    100.0 * SUM(CASE WHEN rrtp.subject_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS rrt_pct
  FROM admission_comorbidity ac
  LEFT JOIN vent_patients vp
    ON ac.subject_id = vp.subject_id AND ac.hadm_id = vp.hadm_id
  LEFT JOIN vasopressor_patients vsp
    ON ac.subject_id = vsp.subject_id AND ac.hadm_id = vsp.hadm_id
  LEFT JOIN rrt_patients rrtp
    ON ac.subject_id = rrtp.subject_id AND ac.hadm_id = rrtp.hadm_id
  GROUP BY ac.stroke_type, ac.los_group, ac.comorbidity_group
)
SELECT
  stroke_type,
  los_group,
  comorbidity_group,
  n_patients,
  ROUND(mortality_pct, 1) AS mortality_pct,
  median_los,
  ROUND(mech_vent_pct, 1) AS mech_vent_pct,
  ROUND(vasopressor_pct, 1) AS vasopressor_pct,
  ROUND(rrt_pct, 1) AS rrt_pct
FROM final
ORDER BY stroke_type, los_group, comorbidity_group;