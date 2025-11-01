WITH hf_admissions AS (
  -- Identify admissions with primary heart failure diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS hosp_los_hours,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),

comorbidities AS (
  -- Count secondary diagnoses to estimate comorbidity burden
  SELECT
    hadm_id,
    COUNT(*) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num > 1
  GROUP BY hadm_id
),

icu_status AS (
  -- Determine if patient had ICU stay
  SELECT
    hadm_id,
    MAX(CASE WHEN stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

interventions AS (
  -- Identify MV, vasopressors, RRT
  SELECT
    ce.hadm_id,
    MAX(CASE WHEN di.label LIKE '%ventil%' THEN 1 ELSE 0 END) AS mechanical_ventilation,
    MAX(CASE WHEN di.label LIKE '%norepinephrine%' OR di.label LIKE '%dopamine%' THEN 1 ELSE 0 END) AS vasopressor,
    MAX(CASE WHEN di.label LIKE '%dialysis%' THEN 1 ELSE 0 END) AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.label LIKE '%ventil%'
    OR di.label LIKE '%norepinephrine%'
    OR di.label LIKE '%dopamine%'
    OR di.label LIKE '%dialysis%'
  GROUP BY ce.hadm_id
),

final_data AS (
  SELECT
    hf.hadm_id,
    hf.hospital_expire_flag,
    COALESCE(icu.had_icu, 0) AS had_icu,
    CASE WHEN hf.hosp_los_hours < 192 THEN '<8' ELSE '>=8' END AS los_group,
    CASE
      WHEN COALESCE(cm.comorbidity_count, 0) < 3 THEN 'Low'
      WHEN cm.comorbidity_count BETWEEN 3 AND 5 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_burden,
    COALESCE(iv.mechanical_ventilation, 0) AS mechanical_ventilation,
    COALESCE(iv.vasopressor, 0) AS vasopressor,
    COALESCE(iv.rrt, 0) AS rrt
  FROM hf_admissions hf
  LEFT JOIN comorbidities cm ON hf.hadm_id = cm.hadm_id
  LEFT JOIN icu_status icu ON hf.hadm_id = icu.hadm_id
  LEFT JOIN interventions iv ON hf.hadm_id = iv.hadm_id
)

SELECT
  had_icu,
  los_group,
  comorbidity_burden,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(mechanical_ventilation) AS mv_prevalence,
  AVG(vasopressor) AS vaso_prevalence,
  AVG(rrt) AS rrt_prevalence
FROM final_data
GROUP BY had_icu, los_group, comorbidity_burden
ORDER BY had_icu, los_group, comorbidity_burden;