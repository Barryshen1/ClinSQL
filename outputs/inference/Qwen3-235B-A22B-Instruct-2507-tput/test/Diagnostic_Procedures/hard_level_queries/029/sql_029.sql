WITH patient_icu_age AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 68 AND 78
),

vasopressor_drugs AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('norepinephrine', 'vasopressin', 'dopamine', 'epinephrine', 'phenylephrine')
    AND linksto = 'inputevents'
),

vasopressor_exposure AS (
  SELECT DISTINCT
    pia.subject_id,
    pia.hadm_id,
    pia.stay_id,
    pia.intime
  FROM patient_icu_age pia
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON pia.stay_id = ie.stay_id
  JOIN vasopressor_drugs v
    ON ie.itemid = v.itemid
  WHERE ie.starttime >= pia.intime
    AND ie.starttime <= DATETIME_ADD(pia.intime, INTERVAL 72 HOUR)
),

lab_counts AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN vasopressor_exposure v ON le.hadm_id = v.hadm_id
  WHERE le.charttime >= v.intime
    AND le.charttime <= DATETIME_ADD(v.intime, INTERVAL 72 HOUR)
  GROUP BY le.hadm_id
),

imaging_categories AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE category = 'Imaging'
),

imaging_counts AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN vasopressor_exposure v ON h.hadm_id = v.hadm_id
  JOIN imaging_categories i ON h.hcpcs_cd = i.code
  WHERE h.chartdate >= DATE(v.intime)
    AND h.chartdate <= DATE_ADD(DATE(v.intime), INTERVAL 3 DAY)
  GROUP BY h.hadm_id
),

diagnostic_load AS (
  SELECT
    v.stay_id,
    v.hadm_id,
    COALESCE(l.lab_count, 0) + COALESCE(i.imaging_count, 0) AS total_diagnostic_count
  FROM vasopressor_exposure v
  LEFT JOIN lab_counts l ON v.hadm_id = l.hadm_id
  LEFT JOIN imaging_counts i ON v.hadm_id = i.hadm_id
),

quartiles AS (
  SELECT
    dl.stay_id,
    dl.hadm_id,
    dl.total_diagnostic_count,
    NTILE(4) OVER (ORDER BY dl.total_diagnostic_count) AS quartile
  FROM diagnostic_load dl
),

procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS procedure_count
  FROM (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    UNION ALL
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.procedureevents` WHERE hadm_id IS NOT NULL
  ) AS sub
  GROUP BY hadm_id
),

admission_outcomes AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hosp_los,
    a.hospital_expire_flag,
    a.dischtime,
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN vasopressor_exposure v ON a.hadm_id = v.hadm_id
),

readmission_flag AS (
  SELECT
    hadm_id,
    CASE
      WHEN next_admittime IS NOT NULL
       AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30
        THEN 1
      ELSE 0
    END AS thirty_day_readmit
  FROM admission_outcomes
  WHERE dischtime IS NOT NULL
)

SELECT
  q.quartile,
  AVG(COALESCE(pc.procedure_count, 0)) AS avg_procedure_count,
  AVG(ao.hosp_los) AS avg_hospital_los,
  AVG(ao.hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(COALESCE(r.thirty_day_readmit, 0)) AS thirty_day_readmission_rate
FROM quartiles q
LEFT JOIN procedure_counts pc ON q.hadm_id = pc.hadm_id
LEFT JOIN admission_outcomes ao ON q.hadm_id = ao.hadm_id
LEFT JOIN readmission_flag r ON q.hadm_id = r.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;