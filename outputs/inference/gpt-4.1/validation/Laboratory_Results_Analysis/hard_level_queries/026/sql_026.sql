WITH hepatic_failure_icds AS (
  -- ICD-9: 570 (Acute necrosis of liver), 572.x (other liver failure)
  -- ICD-10: K72.x (hepatic failure)
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND (icd_code LIKE '570%' OR icd_code LIKE '572%'))
     OR (icd_version = 10 AND icd_code LIKE 'K72%')
),
hepatic_failure_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN hepatic_failure_icds h
    ON d.icd_code = h.icd_code AND d.icd_version = h.icd_version
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN hepatic_failure_admissions hfa
    ON a.subject_id = hfa.subject_id AND a.hadm_id = hfa.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),
cohort_icu AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    c.hospital_expire_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
),
cohort_labs_48h AS (
  SELECT
    ci.stay_id,
    COUNTIF(l.flag = 'abnormal') AS critical_lab_count
  FROM cohort_icu ci
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON ci.subject_id = l.subject_id AND ci.hadm_id = l.hadm_id
  WHERE l.charttime >= ci.intime
    AND l.charttime <= TIMESTAMP_ADD(ci.intime, INTERVAL 48 HOUR)
  GROUP BY ci.stay_id
),
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),
general_inpatients_icu AS (
  SELECT
    gi.subject_id,
    gi.hadm_id,
    i.stay_id,
    i.intime
  FROM general_inpatients gi
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON gi.subject_id = i.subject_id AND gi.hadm_id = i.hadm_id
),
general_labs_48h AS (
  SELECT
    giu.stay_id,
    COUNTIF(l.flag = 'abnormal') AS critical_lab_count
  FROM general_inpatients_icu giu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON giu.subject_id = l.subject_id AND giu.hadm_id = l.hadm_id
  WHERE l.charttime >= giu.intime
    AND l.charttime <= TIMESTAMP_ADD(giu.intime, INTERVAL 48 HOUR)
  GROUP BY giu.stay_id
)
SELECT
  -- Hepatic failure cohort metrics
  COUNT(DISTINCT cohort_icu.stay_id) AS hepatic_failure_icu_stays,
  AVG(cohort_icu.los) AS avg_los_days,
  AVG(CASE WHEN cohort_icu.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hospital_mortality_rate,
  NULL AS max_instability_score, -- SOFA not available in MIMIC-IV tables
  AVG(cl.critical_lab_count) AS avg_critical_labs_per_stay,
  -- General inpatients metrics
  AVG(gl.critical_lab_count) AS avg_critical_labs_general_inpatients
FROM cohort_icu
LEFT JOIN cohort_labs_48h cl ON cohort_icu.stay_id = cl.stay_id
LEFT JOIN general_labs_48h gl ON TRUE -- For overall average, not per-stay comparison;