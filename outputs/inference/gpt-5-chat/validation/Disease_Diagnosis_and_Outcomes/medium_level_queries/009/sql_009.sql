WITH sepsis_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender,
    adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 53 AND 63
    -- include sepsis
    AND (
      (diag.icd_version = 9 AND (
         diag.icd_code LIKE '038%' OR diag.icd_code IN ('99591','99592')
      ))
      OR
      (diag.icd_version = 10 AND (
         diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R6520%' OR diag.icd_code LIKE 'R6521%'
      ))
    )
    -- exclude septic shock
    AND adm.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE (d.icd_version = 9 AND d.icd_code = '78552')
         OR (d.icd_version = 10 AND d.icd_code LIKE 'R6521%')
    )
),
los_calc AS (
  SELECT sa.*,
    DATETIME_DIFF(sa.dischtime, sa.admittime, HOUR)/24.0 AS los_days
  FROM sepsis_admissions sa
),
los_group AS (
  SELECT *,
    CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_group
  FROM los_calc
),
icu_flags AS (
  SELECT l.hadm_id,
    CASE WHEN MIN(DATETIME_DIFF(icu.intime, l.admittime, HOUR)) <= 24 THEN 1 ELSE 0 END AS day1_icu_flag
  FROM los_group l
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON l.subject_id = icu.subject_id AND l.hadm_id = icu.hadm_id
  GROUP BY l.hadm_id
),
mech_vent AS (
  SELECT DISTINCT l.hadm_id, 1 AS mech_vent_flag
  FROM los_group l
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON l.subject_id = proc.subject_id AND l.hadm_id = proc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON proc.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%vent%'
),
vasopressors AS (
  SELECT DISTINCT l.hadm_id, 1 AS vaso_flag
  FROM los_group l
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` inp
    ON l.subject_id = inp.subject_id AND l.hadm_id = inp.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON inp.itemid = di.itemid
  WHERE REGEXP_CONTAINS(LOWER(di.label), r'norepinephrine|epinephrine|phenylephrine|vasopressin|dopamine')
),
rrt AS (
  SELECT DISTINCT l.hadm_id, 1 AS rrt_flag
  FROM los_group l
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON l.subject_id = proc.subject_id AND l.hadm_id = proc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON proc.itemid = di.itemid
  WHERE REGEXP_CONTAINS(LOWER(di.label), r'dialysis|hemofiltration|ultrafiltration')
)
SELECT
  lg.los_group,
  icu.day1_icu_flag,
  COUNT(DISTINCT lg.hadm_id) AS n_admissions,
  ROUND(AVG(lg.hospital_expire_flag)*100,1) AS mortality_pct,
  ROUND(AVG(IF(mv.mech_vent_flag=1,1,0))*100,1) AS mech_vent_pct,
  ROUND(AVG(IF(vs.vaso_flag=1,1,0))*100,1) AS vasopressor_pct,
  ROUND(AVG(IF(rr.rrt_flag=1,1,0))*100,1) AS rrt_pct
FROM los_group lg
LEFT JOIN icu_flags icu ON lg.hadm_id = icu.hadm_id
LEFT JOIN mech_vent mv ON lg.hadm_id = mv.hadm_id
LEFT JOIN vasopressors vs ON lg.hadm_id = vs.hadm_id
LEFT JOIN rrt rr ON lg.hadm_id = rr.hadm_id
GROUP BY lg.los_group, icu.day1_icu_flag
ORDER BY lg.los_group, icu.day1_icu_flag;