WITH age_calc AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
),

stroke_codes AS (
  SELECT
    hadm_id,
    MAX(CASE
      WHEN SUBSTR(d_icd.icd_code, 1, 3) = 'I63' THEN 1 ELSE 0
    END) AS ischemic,
    MAX(CASE
      WHEN SUBSTR(d_icd.icd_code, 1, 3) IN ('I60', 'I61', 'I62') THEN 1 ELSE 0
    END) AS hemorrhagic
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  GROUP BY hadm_id
),

stroke_patients AS (
  SELECT
    ac.*
  FROM age_calc ac
  INNER JOIN stroke_codes sc
    ON ac.hadm_id = sc.hadm_id
  WHERE (sc.ischemic = 1 AND sc.hemorrhagic = 0)
     OR (sc.hemorrhagic = 1 AND sc.ischemic = 0)
),

stroke_type_labeled AS (
  SELECT
    sp.*,
    CASE
      WHEN sc.ischemic = 1 THEN 'ischemic'
      WHEN sc.hemorrhagic = 1 THEN 'hemorrhagic'
    END AS stroke_type
  FROM stroke_patients sp
  INNER JOIN stroke_codes sc
    ON sp.hadm_id = sc.hadm_id
),

hospital_los AS (
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS hosp_los_days
  FROM stroke_type_labeled
),

comorbidities AS (
  SELECT
    diag.hadm_id,
    COUNT(*) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE
    (SUBSTR(d_icd.icd_code, 1, 3) = 'I50' OR
     SUBSTR(d_icd.icd_code, 1, 4) IN ('I480', 'I482', 'I489') OR
     SUBSTR(d_icd.icd_code, 1, 3) IN ('I09', 'I34', 'I35', 'I36', 'I37', 'I38', 'I39') OR
     SUBSTR(d_icd.icd_code, 1, 3) IN ('J44', 'J43', 'J42') OR
     SUBSTR(d_icd.icd_code, 1, 3) IN ('E10', 'E11', 'E13') OR
     SUBSTR(d_icd.icd_code, 1, 3) = 'N18' OR
     SUBSTR(d_icd.icd_code, 1, 3) = 'I65')
  GROUP BY diag.hadm_id
),

comorbidity_burden AS (
  SELECT
    hadm_id,
    CASE
      WHEN comorbidity_count = 0 THEN 'low'
      WHEN comorbidity_count BETWEEN 1 AND 2 THEN 'medium'
      WHEN comorbidity_count >= 3 THEN 'high'
    END AS comorbidity_group
  FROM comorbidities
),

icu_procedures AS (
  SELECT
    pe.hadm_id,
    MAX(CASE WHEN di.label = 'Mechanical Ventilation' THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN ie.itemid IN (
      SELECT itemid FROM `physionet-data.mimiciv_3_1_icu`.d_items
      WHERE LOWER(label) IN ('vasopressin', 'norepinephrine', 'epinephrine', 'dopamine', 'dobutamine')
    ) THEN 1 ELSE 0 END) AS vasopressors,
    MAX(CASE WHEN di.label IN ('Dialysis', 'CRRT', 'Hemodialysis') THEN 1 ELSE 0 END) AS rrt
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON pe.itemid = di.itemid
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.inputevents ie
    ON pe.hadm_id = ie.hadm_id AND pe.stay_id = ie.stay_id AND pe.charttime = ie.starttime
  GROUP BY pe.hadm_id
)

SELECT
  stl.stroke_type,
  CASE WHEN hlos.hosp_los_days <= 5 THEN '≤5' ELSE '>5' END AS los_group,
  COALESCE(cb.comorbidity_group, 'low') AS comorbidity_group,
  AVG(CAST(hlos.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
  APPROX_QUANTILES(hlos.hosp_los_days, 2)[OFFSET(1)] AS median_los_days,
  AVG(COALESCE(ip.mech_vent, 0)) * 100 AS mech_vent_pct,
  AVG(COALESCE(ip.vasopressors, 0)) * 100 AS vasopressors_pct,
  AVG(COALESCE(ip.rrt, 0)) * 100 AS rrt_pct
FROM hospital_los hlos
INNER JOIN stroke_type_labeled stl
  ON hlos.hadm_id = stl.hadm_id
LEFT JOIN comorbidity_burden cb
  ON hlos.hadm_id = cb.hadm_id
LEFT JOIN icu_procedures ip
  ON hlos.hadm_id = ip.hadm_id
GROUP BY stl.stroke_type, los_group, comorbidity_group
ORDER BY stl.stroke_type, los_group, comorbidity_group;